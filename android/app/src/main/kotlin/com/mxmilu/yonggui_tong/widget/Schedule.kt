package com.mxmilu.yonggui_tong.widget

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.TimeZone

/** `GET /Api/Stations/ScheduleTime/{StationId}`, the same endpoint the app uses. */
object ScheduleClient {
    private const val BASE = "https://metroinfo.ditiego.net/Api/Stations/ScheduleTime/"

    fun fetch(stationId: Int): JSONArray {
        val connection = URL(BASE + stationId).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) throw IOException("HTTP ${connection.responseCode}")
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            if (json.optInt("Code") != 200) throw IOException("Code ${json.optInt("Code")}")
            return json.optJSONArray("Data") ?: JSONArray()
        } finally {
            connection.disconnect()
        }
    }
}

data class TrainWindow(val arriveAt: Long, val departAt: Long) {
    fun dwelling(now: Long): Boolean = now >= arriveAt && now < departAt
    fun nextBoundary(now: Long): Long = if (now < arriveAt) arriveAt else departAt
}

/** Beijing arrival/departure windows, anchored to the fetch rather than the redraw day. */
object Timetable {
    private val beijing: TimeZone = TimeZone.getTimeZone("GMT+08:00")
    private const val HORIZON = 6 * 60 * 60 * 1000L
    private const val DAY = 24 * 60 * 60 * 1000L

    /** Keep a train through its published departure, including nonpositive arrival durations. */
    fun upcoming(schedule: CachedSchedule, line: Int, flag: Int, now: Long): List<TrainWindow> {
        val result = mutableSetOf<TrainWindow>()
        for (index in 0 until schedule.data.length()) {
            val block = schedule.data.optJSONObject(index) ?: continue
            if (block.optInt("LineId") != line || block.optInt("Flag") != flag) continue
            val runs = block.optJSONArray("StationRunTimes") ?: continue
            for (run in 0 until runs.length()) {
                val entry = runs.optJSONObject(run) ?: continue
                val window = resolve(entry, schedule.fetchedAt) ?: continue
                if (window.departAt > now) result += window
            }
        }
        return result.sortedWith(compareBy<TrainWindow> { it.arriveAt }.thenBy { it.departAt })
    }

    fun resolve(entry: JSONObject, fetchedAt: Long): TrainWindow? {
        val arrivalDuration = entry.optDouble("IntimeDura", Double.NaN)
        val departureDuration = entry.optDouble("OutTimeDura", Double.NaN)
        if (!arrivalDuration.isFinite() || !departureDuration.isFinite()) return null
        if (arrivalDuration == -60.0 && departureDuration == -60.0 &&
            entry.optString("IntimeStr") == entry.optString("OutTimeStr")) return null
        if (departureDuration <= 0) return null
        val arrival = arrivalAt(entry, fetchedAt) ?: return null
        var departure = toMillis(entry.optString("OutTimeStr"), arrival) ?: return null
        if (departure < arrival && hour(arrival) >= 18 && hour(departure) < 6) departure += DAY
        if (departure < arrival || departure <= fetchedAt || departure - fetchedAt >= HORIZON ||
            arrival - fetchedAt >= HORIZON || fetchedAt - arrival >= HORIZON ||
            departure - arrival >= HORIZON) return null
        return TrainWindow(arrival, departure)
    }

    /** Only a still-dwelling cached run may survive omission from a fresh response. */
    fun mergeDwelling(previous: CachedSchedule?, fresh: JSONArray, fetchedAt: Long): JSONArray {
        if (previous == null) return fresh
        for (index in 0 until previous.data.length()) {
            val oldBlock = previous.data.optJSONObject(index) ?: continue
            val line = oldBlock.optInt("LineId")
            val flag = oldBlock.optInt("Flag")
            val oldRuns = oldBlock.optJSONArray("StationRunTimes") ?: continue
            var target: JSONObject? = null
            val freshArrivals = mutableSetOf<Long>()
            for (freshIndex in 0 until fresh.length()) {
                val block = fresh.optJSONObject(freshIndex) ?: continue
                if (block.optInt("LineId") != line || block.optInt("Flag") != flag) continue
                target = block
                val runs = block.optJSONArray("StationRunTimes") ?: continue
                for (run in 0 until runs.length()) {
                    val entry = runs.optJSONObject(run) ?: continue
                    arrivalAt(entry, fetchedAt)?.let { freshArrivals += it }
                }
            }
            for (run in 0 until oldRuns.length()) {
                val entry = oldRuns.optJSONObject(run) ?: continue
                val window = resolve(entry, previous.fetchedAt) ?: continue
                if (!window.dwelling(fetchedAt) || !freshArrivals.add(window.arriveAt)) continue
                val block = target ?: JSONObject(oldBlock.toString()).apply {
                    put("StationRunTimes", JSONArray())
                    fresh.put(this)
                    target = this
                }
                val runs = block.optJSONArray("StationRunTimes") ?: JSONArray().also {
                    block.put("StationRunTimes", it)
                }
                // Rebase only the remaining durations; retain the API's actual scheduled times.
                runs.put(JSONObject(entry.toString()).apply {
                    put("IntimeDura", (window.arriveAt - fetchedAt) / 1000.0)
                    put("OutTimeDura", (window.departAt - fetchedAt) / 1000.0)
                })
            }
        }
        return fresh
    }

    private fun arrivalAt(entry: JSONObject, fetchedAt: Long): Long? {
        var arrival = toMillis(entry.optString("IntimeStr"), fetchedAt) ?: return null
        val duration = entry.optDouble("IntimeDura", Double.NaN)
        // Limit date correction to the midnight edges, with duration sign as corroboration.
        if (arrival < fetchedAt && hour(fetchedAt) >= 18 && hour(arrival) < 6 && duration > 0) {
            arrival += DAY
        } else if (arrival > fetchedAt && hour(fetchedAt) < 6 && hour(arrival) >= 18 && duration <= 0) {
            arrival -= DAY
        }
        return arrival
    }

    private fun hour(at: Long): Int =
        Calendar.getInstance(beijing).apply { timeInMillis = at }.get(Calendar.HOUR_OF_DAY)

    /** Fewest upcoming runs over the directions present in the schedule; null when it lists none. */
    fun thinnest(schedule: CachedSchedule, now: Long): Int? =
        (0 until schedule.data.length()).mapNotNull { index ->
            val block = schedule.data.optJSONObject(index) ?: return@mapNotNull null
            upcoming(schedule, block.optInt("LineId"), block.optInt("Flag"), now).size
        }.minOrNull()

    fun clock(at: Long): String {
        val calendar = Calendar.getInstance(beijing).apply { timeInMillis = at }
        return "%02d:%02d".format(calendar.get(Calendar.HOUR_OF_DAY), calendar.get(Calendar.MINUTE))
    }

    private fun toMillis(hms: String, anchor: Long): Long? {
        val parts = hms.split(':')
        if (parts.size != 3) return null
        val hours = parts[0].toIntOrNull() ?: return null
        val minutes = parts[1].toIntOrNull() ?: return null
        val seconds = parts[2].toIntOrNull() ?: return null
        if (hours !in 0..23 || minutes !in 0..59 || seconds !in 0..59) return null
        val calendar = Calendar.getInstance(beijing).apply {
            timeInMillis = anchor
            set(Calendar.HOUR_OF_DAY, hours)
            set(Calendar.MINUTE, minutes)
            set(Calendar.SECOND, seconds)
            set(Calendar.MILLISECOND, 0)
        }
        return calendar.timeInMillis
    }
}
