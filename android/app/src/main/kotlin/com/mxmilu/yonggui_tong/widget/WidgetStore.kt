package com.mxmilu.yonggui_tong.widget

import android.content.Context
import org.json.JSONArray

data class WidgetDirection(val line: Int, val flag: Int, val label: String, val color: Int)

data class WidgetStation(val id: Int, val name: String, val directions: List<WidgetDirection>)

/** Last `ScheduleTime` payload (`Data` array) for a station; [failedAt] is set when a later fetch failed. */
data class CachedSchedule(val data: JSONArray, val fetchedAt: Long, val failedAt: Long?)

/** Favorites pushed by the app, the station each widget shows, and cached schedules. */
class WidgetStore(context: Context) {
    private val prefs = context.getSharedPreferences("yonggui_widget", Context.MODE_PRIVATE)

    fun saveStations(json: String) {
        prefs.edit().putString(KEY_STATIONS, json).apply()
    }

    fun stations(): List<WidgetStation> {
        val array = runCatching { JSONArray(prefs.getString(KEY_STATIONS, "[]")) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).map { index ->
            val station = array.getJSONObject(index)
            val directions = station.getJSONArray("directions")
            WidgetStation(
                id = station.getInt("id"),
                name = station.getString("name"),
                directions = (0 until directions.length()).map {
                    val direction = directions.getJSONObject(it)
                    WidgetDirection(
                        line = direction.getInt("line"),
                        flag = direction.getInt("flag"),
                        label = direction.getString("label"),
                        color = direction.getLong("color").toInt(),
                    )
                },
            )
        }
    }

    /** Position of the widget's station among the favorites, kept in range as favorites change. */
    fun position(widgetId: Int, count: Int): Int =
        if (count == 0) 0 else prefs.getInt(indexKey(widgetId), 0).mod(count)

    fun stationFor(widgetId: Int): WidgetStation? {
        val stations = stations()
        return if (stations.isEmpty()) null else stations[position(widgetId, stations.size)]
    }

    fun advance(widgetId: Int) {
        val count = stations().size
        if (count > 0) prefs.edit().putInt(indexKey(widgetId), (position(widgetId, count) + 1) % count).apply()
    }

    fun forget(widgetIds: IntArray) {
        prefs.edit().apply { widgetIds.forEach { remove(indexKey(it)) } }.apply()
    }

    fun schedule(stationId: Int): CachedSchedule? {
        val raw = prefs.getString(scheduleKey(stationId), null) ?: return null
        val data = runCatching { JSONArray(raw) }.getOrNull() ?: return null
        val failedAt = prefs.getLong(failedKey(stationId), 0L)
        val fetchedAt = prefs.getLong(fetchedKey(stationId), 0L)
        return CachedSchedule(data, fetchedAt, failedAt.takeIf { it > fetchedAt })
    }

    fun saveSchedule(stationId: Int, data: JSONArray, fetchedAt: Long) {
        val merged = Timetable.mergeDwelling(schedule(stationId), data, fetchedAt)
        prefs.edit()
            .putString(scheduleKey(stationId), merged.toString())
            .putLong(fetchedKey(stationId), fetchedAt)
            .remove(failedKey(stationId))
            .apply()
    }

    fun markFailure(stationId: Int, at: Long) {
        prefs.edit().putLong(failedKey(stationId), at).apply()
    }

    /** Time of the last fetch attempt, successful or not, for the 60 s per-station limit. */
    fun lastAttempt(stationId: Int): Long =
        maxOf(prefs.getLong(fetchedKey(stationId), 0L), prefs.getLong(failedKey(stationId), 0L))

    private fun indexKey(widgetId: Int) = "index_$widgetId"
    private fun scheduleKey(stationId: Int) = "schedule_$stationId"
    private fun fetchedKey(stationId: Int) = "fetched_$stationId"
    private fun failedKey(stationId: Int) = "failed_$stationId"

    private companion object {
        const val KEY_STATIONS = "stations"
    }
}
