package com.mxmilu.yonggui_tong.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import com.mxmilu.yonggui_tong.MainActivity
import com.mxmilu.yonggui_tong.R

/** Home screen widget: next train of every direction at one favorite station. */
class ArrivalsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        refresh(context, force = false)
    }

    override fun onEnabled(context: Context) {
        WidgetRefreshWorker.schedulePeriodic(context)
    }

    override fun onDisabled(context: Context) {
        WidgetRefreshWorker.cancelAll(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        WidgetStore(context).forget(appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_REFRESH -> refresh(context, force = true)
            ACTION_SWITCH -> {
                val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) WidgetStore(context).advance(widgetId)
                refresh(context, force = false)
            }
        }
    }

    companion object {
        private const val ACTION_REFRESH = "com.mxmilu.yonggui_tong.widget.REFRESH"
        private const val ACTION_SWITCH = "com.mxmilu.yonggui_tong.widget.SWITCH"

        fun widgetIds(context: Context): IntArray = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, ArrivalsWidgetProvider::class.java))

        /** Redraws from cache now, then fetches in the background (at most once per 60 s per station). */
        fun refresh(context: Context, force: Boolean) {
            if (widgetIds(context).isEmpty()) return
            renderAll(context)
            WidgetRefreshWorker.enqueue(context, force)
            WidgetRefreshWorker.schedulePeriodic(context)
        }

        /** Draws every widget from cached data; returns the soonest arrival on screen. */
        fun renderAll(context: Context): Long? {
            val store = WidgetStore(context)
            val manager = AppWidgetManager.getInstance(context)
            val now = System.currentTimeMillis()
            return widgetIds(context).asList().mapNotNull { render(context, manager, store, it, now) }.minOrNull()
        }

        private fun render(context: Context, manager: AppWidgetManager, store: WidgetStore, widgetId: Int, now: Long): Long? {
            val views = RemoteViews(context.packageName, R.layout.widget_arrivals)
            views.setOnClickPendingIntent(R.id.widget_refresh, broadcast(context, ACTION_REFRESH, widgetId))
            views.removeAllViews(R.id.widget_rows)
            val stations = store.stations()
            if (stations.isEmpty()) {
                views.setTextViewText(R.id.widget_station, context.getString(R.string.app_widget_title))
                views.setViewVisibility(R.id.widget_position, View.GONE)
                showMessage(views, context.getString(R.string.widget_no_favorites))
                views.setTextViewText(R.id.widget_footer, "")
                views.setOnClickPendingIntent(R.id.widget_root, openApp(context, "/arrivals", widgetId))
                manager.updateAppWidget(widgetId, views)
                return null
            }
            val position = store.position(widgetId, stations.size)
            val station = stations[position]
            views.setTextViewText(R.id.widget_station, station.name)
            views.setViewVisibility(R.id.widget_position, if (stations.size > 1) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_position, "${position + 1}/${stations.size}")
            views.setOnClickPendingIntent(R.id.widget_header, broadcast(context, ACTION_SWITCH, widgetId))
            views.setOnClickPendingIntent(R.id.widget_root, openApp(context, "/arrivals/${station.id}", widgetId))

            val schedule = store.schedule(station.id)
            var soonest: Long? = null
            if (schedule == null) {
                showMessage(views, context.getString(R.string.widget_loading))
                views.setTextViewText(R.id.widget_footer, "")
            } else {
                views.setViewVisibility(R.id.widget_message, View.GONE)
                for (direction in station.directions) {
                    val next = Timetable.upcoming(schedule, direction.line, direction.flag, now).firstOrNull()
                    val row = RemoteViews(context.packageName, R.layout.widget_arrival_row)
                    row.setInt(R.id.row_bar, "setColorFilter", direction.color)
                    row.setTextViewText(R.id.row_label, direction.label)
                    if (next == null) {
                        row.setTextViewText(R.id.row_time, context.getString(R.string.widget_no_train))
                        row.setViewVisibility(R.id.row_countdown, View.GONE)
                    } else {
                        row.setTextViewText(R.id.row_time, Timetable.clock(next))
                        // A system chronometer keeps counting down without further widget updates.
                        row.setChronometer(R.id.row_countdown, SystemClock.elapsedRealtime() + (next - now), null, true)
                        row.setChronometerCountDown(R.id.row_countdown, true)
                        row.setViewVisibility(R.id.row_countdown, View.VISIBLE)
                        soonest = minOf(soonest ?: next, next)
                    }
                    views.addView(R.id.widget_rows, row)
                }
                val updated = context.getString(R.string.widget_updated, Timetable.clock(schedule.fetchedAt))
                views.setTextViewText(R.id.widget_footer,
                    if (schedule.failedAt != null) "$updated · ${context.getString(R.string.widget_update_failed)}" else updated)
            }
            manager.updateAppWidget(widgetId, views)
            return soonest
        }

        private fun showMessage(views: RemoteViews, message: String) {
            views.setViewVisibility(R.id.widget_message, View.VISIBLE)
            views.setTextViewText(R.id.widget_message, message)
        }

        private fun broadcast(context: Context, action: String, widgetId: Int): PendingIntent {
            val intent = Intent(context, ArrivalsWidgetProvider::class.java)
                .setAction(action)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            return PendingIntent.getBroadcast(context, requestCode(action, widgetId), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        /** Opens the app on a go_router path through Flutter deep linking. */
        private fun openApp(context: Context, path: String, widgetId: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("yonggui://app$path"))
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(context, requestCode("open", widgetId), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun requestCode(action: String, widgetId: Int) = 31 * action.hashCode() + widgetId
    }
}
