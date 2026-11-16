import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme/line_colors.dart';
import '../core/models/station.dart';
import '../core/utils/direction_resolver.dart';
import 'providers.dart';

/// Favorite stations as the Android home screen widget reads them. Station IDs are the
/// Dict-resolved `ScheduleTime` IDs; the widget fetches arrivals itself.
final favoriteWidgetPayloadProvider = Provider<String?>((ref) {
  final catalog = ref.watch(catalogProvider).valueOrNull;
  if (catalog == null) return null;
  final stations = [
    for (final id in ref.watch(favoritesProvider)) ?catalog.stationById(id),
  ];
  return favoriteWidgetPayload(stations, catalog);
});

String favoriteWidgetPayload(List<Station> stations, StationCatalog catalog) => jsonEncode([
  for (final station in stations) {
    'id': station.id,
    'name': station.name,
    'directions': [
      for (final line in station.lineIds)
        for (final flag in const [1, 2]) {
          'line': line,
          'flag': flag,
          'label': DirectionResolver.label(lineId: line, flag: flag, catalog: catalog),
          'color': LineColors.colorOf(line).toARGB32(),
        },
    ],
  },
]);

final widgetPinSupportedProvider = FutureProvider<bool>((ref) => FavoriteWidget.canPin());

abstract final class FavoriteWidget {
  static const _channel = MethodChannel('yonggui/widget');

  /// Hands the payload to the native widget; a no-op off Android.
  static Future<void> sync(String payload) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('sync', payload);
    } on PlatformException catch (error) {
      debugPrint('Widget sync failed: $error');
    } on MissingPluginException {
      // Engine without the native side (tests, add-to-app); nothing to update.
    }
  }

  /// Whether the launcher can add the widget from inside the app (Android 8+ launchers).
  static Future<bool> canPin() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('canPin') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Asks the launcher to place the widget; the launcher shows its own confirmation.
  static Future<bool> pin() async {
    try {
      return await _channel.invokeMethod<bool>('pin') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
