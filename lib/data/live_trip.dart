import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/utils/live_stages.dart';

/// Android Live Updates (status-bar chip; HyperOS 3 island area) for a trip the user starts.
abstract final class LiveTrip {
  static const _channel = MethodChannel('yonggui/live');

  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Starts [plan] (replacing any running trip) and tells the user where it shows up.
  static Future<void> start(BuildContext context, LiveTripPlan plan) async {
    final messenger = ScaffoldMessenger.of(context);
    Map<Object?, Object?>? result;
    try {
      result = await _channel.invokeMethod<Map<Object?, Object?>>('start', jsonEncode(plan.toJson()));
    } on PlatformException catch (error) {
      debugPrint('Live trip failed: $error');
    } on MissingPluginException {
      return;
    }
    messenger.hideCurrentSnackBar();
    if (result?['started'] != true) {
      messenger.showSnackBar(const SnackBar(content: Text('需要通知权限才能在状态栏显示')));
    } else if (result?['focusAllowed'] == true) {
      messenger.showSnackBar(const SnackBar(content: Text('已开始，系统允许超级岛通知；实际展示由系统决定')));
    } else if (result?['promoted'] == true) {
      messenger.showSnackBar(const SnackBar(content: Text('已开始，系统允许实时更新；实际展示由系统决定')));
    } else {
      messenger.showSnackBar(SnackBar(
        content: const Text('已开始常驻通知，暂未获得实时更新或超级岛权限，可查看通知设置'),
        action: SnackBarAction(label: '去开启', onPressed: () => _channel.invokeMethod<void>('openSettings')),
      ));
    }
  }
}
