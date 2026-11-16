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

/** Arrival times from a cached schedule. `IntimeStr` is Beijing time; `IntimeDura <= 0` means no train. */
object Timetable {
    private val beijing: TimeZone = TimeZone.getTimeZone("GMT+08:00")
    private const val HORIZON = 6 * 60 * 60 * 1000L

    /** Upcoming arrivals (epoch ms) for one direction, soonest first. */
    fun upcoming(schedule: CachedSchedule, line: Int, flag: Int, now: Long): List<Long> {
        val result = mutableListOf<Long>()
        for (index in 0 until schedule.data.length()) {
            val block = schedule.data.optJSONObject(index) ?: continue
            if (block.optInt("LineId") != line || block.optInt("Flag") != flag) continue
            val runs = block.optJSONArray("StationRunTimes") ?: continue
            for (run in 0 until runs.length()) {
                val entry = runs.optJSONObject(run) ?: continue
                if (!(entry.optDouble("IntimeDura", 0.0) > 0)) continue
                val at = toMillis(entry.optString("IntimeStr"), schedule.fetchedAt) ?: continue
                if (at > now && at - schedule.fetchedAt < HORIZON) result += at
            }
        }
        return result.sorted()
    }

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
        val parts = hms.split(':').mapNotNull { it.toIntOrNull() }
        if (parts.size != 3 || parts[0] !in 0..23 || parts[1] !in 0..59 || parts[2] !in 0..59) return null
        val calendar = Calendar.getInstance(beijing).apply {
            timeInMillis = anchor
            set(Calendar.HOUR_OF_DAY, parts[0])
            set(Calendar.MINUTE, parts[1])
            set(Calendar.SECOND, parts[2])
            set(Calendar.MILLISECOND, 0)
        }
        val anchorHour = Calendar.getInstance(beijing).apply { timeInMillis = anchor }.get(Calendar.HOUR_OF_DAY)
        // Only a late-night fetch can list early next-day service.
        if (calendar.timeInMillis < anchor && anchorHour >= 18 && parts[0] < 6) calendar.add(Calendar.DAY_OF_MONTH, 1)
        return calendar.timeInMillis
    }
}
