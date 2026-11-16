package com.mxmilu.yonggui_tong.widget

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/**
 * Fetches schedules for the stations on screen and redraws. Runs on demand, every 15 minutes,
 * and right after the soonest train shown arrives so the countdown never runs past zero for long.
 */
class WidgetRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val context = applicationContext
        val store = WidgetStore(context)
        val widgetIds = ArrivalsWidgetProvider.widgetIds(context)
        if (widgetIds.isEmpty()) return@withContext Result.success()
        val force = inputData.getBoolean(KEY_FORCE, false)
        val stations = widgetIds.asList().mapNotNull { store.stationFor(it)?.id }.toSet()
        for (stationId in stations) {
            val now = System.currentTimeMillis()
            if (now - store.lastAttempt(stationId) < MIN_INTERVAL) continue
            val schedule = store.schedule(stationId)
            val running = schedule?.let { Timetable.thinnest(it, now) }
            val due = schedule == null || force || now - schedule.fetchedAt >= STALE_AFTER ||
                (running != null && running <= 1)
            if (!due) continue
            try {
                store.saveSchedule(stationId, ScheduleClient.fetch(stationId), now)
            } catch (error: Exception) {
                store.markFailure(stationId, now)
            }
        }
        scheduleTick(context, ArrivalsWidgetProvider.renderAll(context))
        Result.success()
    }

    companion object {
        private const val KEY_FORCE = "force"
        private const val WORK_NOW = "widget-refresh"
        private const val WORK_TICK = "widget-tick"
        private const val WORK_PERIODIC = "widget-periodic"
        /** Same per-station floor as the app's polling. */
        private const val MIN_INTERVAL = 60_000L
        private const val STALE_AFTER = 10 * 60_000L

        fun enqueue(context: Context, force: Boolean) {
            val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
                .setInputData(workDataOf(KEY_FORCE to force))
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(WORK_NOW, ExistingWorkPolicy.REPLACE, request)
        }

        fun schedulePeriodic(context: Context) {
            val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(WORK_PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun cancelAll(context: Context) {
            WorkManager.getInstance(context).apply {
                cancelUniqueWork(WORK_NOW)
                cancelUniqueWork(WORK_TICK)
                cancelUniqueWork(WORK_PERIODIC)
            }
        }

        private fun scheduleTick(context: Context, soonest: Long?) {
            val manager = WorkManager.getInstance(context)
            if (soonest == null) {
                manager.cancelUniqueWork(WORK_TICK)
                return
            }
            val delay = (soonest - System.currentTimeMillis() + 2_000L).coerceAtLeast(15_000L)
            val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
                .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                .build()
            manager.enqueueUniqueWork(WORK_TICK, ExistingWorkPolicy.REPLACE, request)
        }
    }
}
