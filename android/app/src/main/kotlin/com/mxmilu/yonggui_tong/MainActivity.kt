package com.mxmilu.yonggui_tong

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import com.mxmilu.yonggui_tong.widget.ArrivalsWidgetProvider
import com.mxmilu.yonggui_tong.widget.WidgetStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }
}
