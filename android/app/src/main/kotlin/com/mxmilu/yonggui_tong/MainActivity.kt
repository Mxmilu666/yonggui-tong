package com.mxmilu.yonggui_tong

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import com.mxmilu.yonggui_tong.live.LiveTrip
import com.mxmilu.yonggui_tong.widget.ArrivalsWidgetProvider
import com.mxmilu.yonggui_tong.widget.WidgetStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var onNotificationPermission: ((Boolean) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yonggui/widget").setMethodCallHandler { call, result ->
            val widgets = AppWidgetManager.getInstance(this)
            when (call.method) {
                "sync" -> {
                    WidgetStore(this).saveStations(call.arguments as String)
                    ArrivalsWidgetProvider.refresh(this, force = false)
                    result.success(null)
                }
                "canPin" -> result.success(widgets.isRequestPinAppWidgetSupported)
                "pin" -> result.success(widgets.isRequestPinAppWidgetSupported &&
                    widgets.requestPinAppWidget(ComponentName(this, ArrivalsWidgetProvider::class.java), null, null))
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yonggui/live").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> withNotificationPermission { granted ->
                    val focusAllowed = granted && LiveTrip.start(this, call.arguments as String)
                    result.success(mapOf("started" to granted,
                        "promoted" to (granted && LiveTrip.canPromote(this)), "focusAllowed" to focusAllowed))
                }
                "stop" -> {
                    LiveTrip.stop(this)
                    result.success(null)
                }
                "openSettings" -> {
                    // Settings.ACTION_MANAGE_APP_PROMOTED_NOTIFICATIONS (API 36.1); fall back to the app's notification page.
                    val promoted = Intent("android.settings.MANAGE_APP_PROMOTED_NOTIFICATIONS")
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    val fallback = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    startActivity(if (promoted.resolveActivity(packageManager) != null) promoted else fallback)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun withNotificationPermission(then: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            then(true)
            return
        }
        onNotificationPermission = then
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        onNotificationPermission?.invoke(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        onNotificationPermission = null
    }

    private companion object {
        const val REQUEST_NOTIFICATIONS = 41
    }
}
