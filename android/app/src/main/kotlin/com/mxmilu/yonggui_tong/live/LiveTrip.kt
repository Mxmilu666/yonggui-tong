package com.mxmilu.yonggui_tong.live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.mxmilu.yonggui_tong.MainActivity
import com.mxmilu.yonggui_tong.R
import org.json.JSONObject

/**
 * One user-started trip (waiting for a train, or a journey) shown as an Android 16 Live Update:
 * a promoted ongoing notification whose status-bar chip counts down.
 *
 * Focus permission does not prove that System UI runs the native timer. Both the standard chip
 * text and HyperOS digits keep updating each second, alongside the native timer when allowed.
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
    /** `Notification.EXTRA_SHORT_CRITICAL_TEXT`: the chip / island text. */
    private const val EXTRA_SHORT_CRITICAL_TEXT = "android.shortCriticalText"
    private const val FOCUS_PIC = "miui.focus.pic_metro"
    private const val FOCUS_STOP = "miui.focus.action_stop"
    const val EXTRA_FOCUS_ALLOWED = "focusAllowed"

    private data class Stage(val at: Long, val title: String, val text: String, val chip: String, val countdownTo: Long?)

    /**
     * The notification for a moment. [nextAt] is when it must be rebuilt: the next stage, the end,
     * or the next second of a text countdown. [stageAt] identifies the stage shown.
     */
    class Frame(val notification: Notification, val nextAt: Long, val stageAt: Long)

    fun start(context: Context, payload: String): Boolean {
        val focus = canFocus(context)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TRIP, payload).commit()
        // A foreground service must post its notification; never start one for a trip that is already over.
        if (JSONObject(payload).getLong("endsAt") <= System.currentTimeMillis()) {
            stop(context)
            return focus
        }
        context.startForegroundService(Intent(context, LiveTripService::class.java)
            .putExtra(EXTRA_FOCUS_ALLOWED, focus))
        return focus
    }

    fun stop(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_TRIP).commit()
        context.stopService(Intent(context, LiveTripService::class.java))
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    /** Whether the system will promote it to a Live Update (status-bar chip). */
    fun canPromote(context: Context): Boolean =
        Build.VERSION.SDK_INT >= 36 && context.getSystemService(NotificationManager::class.java).canPostPromotedNotifications()

    /** HyperOS island present and this app allowed to post focus notifications. */
    fun canFocus(context: Context): Boolean {
        if (!Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true)) return false
        val island = runCatching {
            Class.forName("android.os.SystemProperties")
                .getMethod("getBoolean", String::class.java, Boolean::class.javaPrimitiveType)
                .invoke(null, "persist.sys.feature.island", false) as Boolean
        }.getOrDefault(false)
        if (!island) return false
        return runCatching {
            context.contentResolver.call(Uri.parse("content://miui.statusbar.notification.public"), "canShowFocus",
                null, Bundle().apply { putString("package", context.packageName) })
                ?.getBoolean("canShowFocus", false) ?: false
        }.getOrDefault(false)
    }

    /** Parse and prepare once per trip, not on the fallback countdown's second ticks. */
    fun load(context: Context, focus: Boolean): Trip? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TRIP, null) ?: return null
        return runCatching { Trip(context, JSONObject(raw), focus) }.getOrNull()
    }

    class Trip internal constructor(context: Context, trip: JSONObject, private val focus: Boolean) {
        private val endsAt = trip.getLong("endsAt")
        private val stages = trip.getJSONArray("stages").let { array ->
            (0 until array.length()).map {
                val stage = array.getJSONObject(it)
                Stage(stage.getLong("at"), stage.getString("title"), stage.getString("text"), stage.getString("chip"),
                    if (stage.isNull("countdownTo")) null else stage.getLong("countdownTo"))
            }.sortedBy { it.at }
        }
        private val stopTitle = context.getString(R.string.live_stop)
        private val stopIntent = PendingIntent.getBroadcast(context, 1,
            Intent(context, LiveTripReceiver::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        private val openIntent = PendingIntent.getActivity(context, 2,
            Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("yonggui://app" + trip.optString("open", "/")))
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        private val stopAction = Notification.Action.Builder(null, stopTitle, stopIntent).build()
        private val focusPictures = Bundle().apply {
            putParcelable(FOCUS_PIC, Icon.createWithResource(context, R.drawable.ic_stat_metro))
        }
        private val focusActions = Bundle().apply { putParcelable(FOCUS_STOP, stopAction) }
        private var cachedFocusParam: JSONObject? = null
        private var focusTarget: Long? = null
        private val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_metro)
            .setColor(context.getColor(R.color.live_accent))
            .setCategory(Notification.CATEGORY_NAVIGATION)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openIntent)
            .setDeleteIntent(stopIntent)
            .addAction(stopAction)

        init {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL,
                context.getString(R.string.live_channel), NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = context.getString(R.string.live_channel_description)
                setShowBadge(false)
            })
        }

        fun frame(now: Long, previousStageAt: Long?): Frame? {
            val current = stages.lastOrNull { it.at <= now } ?: stages.firstOrNull()
            if (current == null || now >= endsAt) return null
            val stageChanged = current.at != previousStageAt
            if (stageChanged) {
                builder.setContentTitle(current.title)
                    .setContentText(current.text)
                    .setStyle(Notification.BigTextStyle().bigText(current.text))
            }
            val countdownTo = current.countdownTo?.takeIf { it > now }
            if (countdownTo != null) {
                builder.setWhen(countdownTo).setShowWhen(true).setUsesChronometer(true).setChronometerCountDown(true)
            } else {
                builder.setShowWhen(false).setUsesChronometer(false)
            }
            val chip = countdownTo?.let { countdown(it - now) } ?: current.chip
            // Some Android builds merge old notification extras over Builder extras on reuse.
            // Write live fields after build() so each posted notification contains this tick.
            val notification = builder.build()
            notification.extras.putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true)
            notification.extras.putString(EXTRA_SHORT_CRITICAL_TEXT, chip)
            if (focus) {
                // Only rebuild the template on a stage/target change, not on every second tick.
                if (stageChanged || cachedFocusParam == null || focusTarget != countdownTo) {
                    cachedFocusParam = focusParam(current, countdownTo, now, stageChanged, stopTitle)
                    focusTarget = countdownTo
                }
                val param = cachedFocusParam!!.getJSONObject("param_v2")
                param.put("enableFloat", stageChanged)
                if (countdownTo != null) {
                    val digits = param.getJSONObject("param_island").getJSONObject("bigIslandArea")
                        .getJSONObject("sameWidthDigitInfo")
                    digits.put("digit", chip)
                    digits.getJSONObject("timerInfo").put("timerSystemCurrent", now)
                }
                notification.extras.putString("miui.focus.param", cachedFocusParam.toString())
                notification.extras.putBundle("miui.focus.pics", focusPictures)
                notification.extras.putBundle("miui.focus.actions", focusActions)
            }

            var nextAt = minOf(stages.firstOrNull { it.at > now }?.at ?: endsAt, endsAt)
            // Even the final stage must clear its system timer at the target, before the trip ends.
            if (countdownTo != null) nextAt = minOf(nextAt, countdownTo)
            // Keep text moving even when focus is allowed but System UI ignores the native timer.
            if (countdownTo != null) nextAt = minOf(nextAt, now + (countdownTo - now - 1) % 1000 + 1)
            return Frame(notification, nextAt, current.at)
        }
    }

    /** Whole seconds left, rounded up: "02:03", or "1:02:03" past an hour. */
    private fun countdown(remainingMs: Long): String {
        val seconds = (remainingMs + 999) / 1000
        val h = seconds / 3600
        val m = seconds % 3600 / 60
        val s = seconds % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
    }

    /** HyperOS focus notification / island: icon in the small island, label and timer in the big one. */
    private fun focusParam(stage: Stage, countdownTo: Long?, now: Long, popUp: Boolean, stopTitle: String): JSONObject {
        val pic = JSONObject().put("type", 1).put("pic", FOCUS_PIC)
        val left = JSONObject().put("type", 1).put("picInfo", pic)
            .put("textInfo", JSONObject().put("title", stage.chip))
        val big = JSONObject().put("imageTextInfoLeft", left)
        if (countdownTo != null) {
            big.put("sameWidthDigitInfo", JSONObject().put("showHighlightColor", true).put("timerInfo", JSONObject()
                .put("timerType", -1).put("timerWhen", countdownTo)
                .put("timerTotal", countdownTo - stage.at).put("timerSystemCurrent", now)))
        }
        val island = JSONObject().put("islandProperty", 1).put("islandPriority", 2)
            .put("bigIslandArea", big)
            .put("smallIslandArea", JSONObject().put("picInfo", pic))
        val param = JSONObject()
            .put("protocol", 3)
            .put("business", "metro_trip")
            .put("updatable", true)
            .put("ticker", stage.title)
            .put("enableFloat", popUp)
            .put("isShowNotification", true)
            .put("baseInfo", JSONObject().put("type", 1).put("title", stage.title).put("content", stage.text))
            // HyperIsland Kit registers notification actions separately from the template JSON.
            .put("actions", org.json.JSONArray().put(JSONObject().put("type", 2)
                .put("action", FOCUS_STOP).put("actionIntentType", 2).put("actionTitle", stopTitle)))
            .put("param_island", island)
        return JSONObject().put("param_v2", param)
    }
}

/** Holds the trip in the foreground and switches stages exactly on time; stops when it ends. */
class LiveTripService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val render = Runnable { render() }
    private var trip: LiveTrip.Trip? = null
    private val manager by lazy { getSystemService(NotificationManager::class.java) }
    private var stageAt: Long? = null
    private var foreground = false

    /** Handler delays pause while the device sleeps; catch up as soon as the screen is back. */
    private val screenOn = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = render()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        registerReceiver(screenOn, IntentFilter(Intent.ACTION_SCREEN_ON))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        trip = LiveTrip.load(this, intent?.getBooleanExtra(LiveTrip.EXTRA_FOCUS_ALLOWED, false) ?: false)
        stageAt = null
        foreground = false
        render()
        return START_NOT_STICKY
    }

    private fun render() {
        handler.removeCallbacks(render)
        val now = System.currentTimeMillis()
        val frame = trip?.frame(now, stageAt)
        if (frame == null) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        stageAt = frame.stageAt
        if (foreground) {
            manager.notify(LiveTrip.NOTIFICATION_ID, frame.notification)
        } else if (Build.VERSION.SDK_INT >= 34) {
            startForeground(LiveTrip.NOTIFICATION_ID, frame.notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(LiveTrip.NOTIFICATION_ID, frame.notification)
        }
        foreground = true
        handler.postDelayed(render, (frame.nextAt - now + 20).coerceAtLeast(20))
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        trip = null
        unregisterReceiver(screenOn)
        super.onDestroy()
    }
}

/** "结束" action and swipe-away: stop the trip and never repost it. */
class LiveTripReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == LiveTrip.ACTION_STOP) LiveTrip.stop(context)
    }
}
