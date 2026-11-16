package com.mxmilu.yonggui_tong.live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.mxmilu.yonggui_tong.MainActivity
import com.mxmilu.yonggui_tong.R
import org.json.JSONObject

/**
 * One user-started trip (waiting for a train, or a journey) shown as an Android 16 Live Update:
 * a promoted ongoing notification whose status-bar chip counts down. HyperOS 3 shows the chip in
 * its island area; older systems keep it as an ongoing notification.
 *
 * The app sends every stage up front. [LiveTripService] keeps the trip in the foreground so stage
 * switches happen on time (deferred background jobs were minutes late) and stops at the end.
 */
object LiveTrip {
    const val NOTIFICATION_ID = 7001
    const val ACTION_STOP = "com.mxmilu.yonggui_tong.live.STOP"
    private const val CHANNEL = "live_trip"
    private const val PREFS = "yonggui_live"
    private const val KEY_TRIP = "trip"
    /** `Notification.EXTRA_REQUEST_PROMOTED_ONGOING`; the extra works where the setter does not exist yet. */
    private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"

    private data class Stage(val at: Long, val title: String, val text: String, val countdownTo: Long?)

    /** The notification for [now] and when the next stage starts (or the trip ends). */
    class Frame(val notification: Notification, val nextAt: Long)

    fun start(context: Context, payload: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TRIP, payload).commit()
        // A foreground service must post its notification; never start one for a trip that is already over.
        if (frame(context, System.currentTimeMillis()) == null) return stop(context)
        context.startForegroundService(Intent(context, LiveTripService::class.java))
    }

    fun stop(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_TRIP).commit()
        context.stopService(Intent(context, LiveTripService::class.java))
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    /** Whether the system will promote it to a Live Update (status-bar chip). */
    fun canPromote(context: Context): Boolean =
        Build.VERSION.SDK_INT >= 36 && context.getSystemService(NotificationManager::class.java).canPostPromotedNotifications()

    /** Null once the trip is over or missing. */
    fun frame(context: Context, now: Long): Frame? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TRIP, null) ?: return null
        val trip = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        val endsAt = trip.getLong("endsAt")
        val stages = trip.getJSONArray("stages").let { array ->
            (0 until array.length()).map {
                val stage = array.getJSONObject(it)
                Stage(stage.getLong("at"), stage.getString("title"), stage.getString("text"),
                    if (stage.isNull("countdownTo")) null else stage.getLong("countdownTo"))
            }.sortedBy { it.at }
        }
        val current = stages.lastOrNull { it.at <= now } ?: stages.firstOrNull()
        if (current == null || now >= endsAt) return null

        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL,
            context.getString(R.string.live_channel), NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = context.getString(R.string.live_channel_description)
            setShowBadge(false)
        })
        val stopIntent = PendingIntent.getBroadcast(context, 1,
            Intent(context, LiveTripReceiver::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val openIntent = PendingIntent.getActivity(context, 2,
            Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("yonggui://app" + trip.optString("open", "/")))
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_metro)
            .setColor(context.getColor(R.color.live_accent))
            .setContentTitle(current.title)
            .setContentText(current.text)
            .setStyle(Notification.BigTextStyle().bigText(current.text))
            .setCategory(Notification.CATEGORY_NAVIGATION)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openIntent)
            .setDeleteIntent(stopIntent)
            .addAction(Notification.Action.Builder(null, context.getString(R.string.live_stop), stopIntent).build())
        val countdownTo = current.countdownTo
        if (countdownTo != null && countdownTo > now) {
            // The chip shows this timer while it is positive.
            builder.setWhen(countdownTo).setShowWhen(true).setUsesChronometer(true).setChronometerCountDown(true)
        } else {
            builder.setShowWhen(false)
        }
        builder.extras.putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true)
        return Frame(builder.build(), stages.firstOrNull { it.at > now }?.at ?: endsAt)
    }
}

/** Holds the trip in the foreground and switches stages exactly on time; stops when it ends. */
class LiveTripService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val render = Runnable { render() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        render()
        return START_NOT_STICKY
    }

    private fun render() {
        handler.removeCallbacks(render)
        val now = System.currentTimeMillis()
        val frame = LiveTrip.frame(this, now)
        if (frame == null) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(LiveTrip.NOTIFICATION_ID, frame.notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(LiveTrip.NOTIFICATION_ID, frame.notification)
        }
        handler.postDelayed(render, (frame.nextAt - now + 300).coerceAtLeast(500))
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}

/** "结束" action and swipe-away: stop the trip and never repost it. */
class LiveTripReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == LiveTrip.ACTION_STOP) LiveTrip.stop(context)
    }
}
