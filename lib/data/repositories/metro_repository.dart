import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/metro_api.dart';
import '../../core/models/arrival.dart';
import '../../core/models/station.dart';
import '../../core/utils/station_resolver.dart';

class MetroRepository {
  MetroRepository({required this.preferences, Dio? dio,
    DateTime Function()? clock, Future<void> Function(Duration)? delay})
      : _api = MetroApi(dio: dio, delay: delay), _clock = clock ?? DateTime.now;
  static const catalogCacheKey = 'metro.catalog.v1';
  final SharedPreferences preferences;
  final MetroApi _api;
  final DateTime Function() _clock;
  final _catalogUpdates = StreamController<StationCatalog>.broadcast();
  Stream<StationCatalog> get catalogUpdates => _catalogUpdates.stream;
  StationCatalog? _catalog;
  Future<StationCatalog>? _catalogFlight;
  int _cacheGeneration = 0;
  final _arrivalCache = <int, ArrivalSnapshot>{};
  final _arrivalFlights = <int, Future<ArrivalSnapshot>>{};
  final _lastAttempt = <int, DateTime>{};
  final _arrivalErrors = <int, Object>{};
  Future<void> _arrivalQueue = Future.value();


  Future<StationCatalog?> cachedCatalog() async {
    if (_catalog != null) return _catalog;
    final raw = preferences.getString(catalogCacheKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final dictionary = parseDictionary(data['dictionary']);
      final entries = (data['entries'] as List).map((e) =>
        StationEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      _catalog = StationCatalog(stations: resolveStations(entries, dictionary),
        dictionary: dictionary, updatedAt: DateTime.parse(data['updatedAt'] as String));
      return _catalog;
    } catch (_) {
      await preferences.remove(catalogCacheKey);
      return null;
    }
  }

  Future<StationCatalog> loadCatalog({bool force = false}) async {
    if (!force) {
      final cached = await cachedCatalog();
      if (cached != null) {
        if (_clock().toUtc().difference(cached.updatedAt) >= const Duration(hours: 24)) {
          unawaited(_refreshCatalog().catchError((Object error, StackTrace stack) {
            if (!_catalogUpdates.isClosed) _catalogUpdates.addError(error, stack);
            return cached;
          }));
        }
        return cached;
      }
    }
    return _refreshCatalog();
  }

  Future<StationCatalog> _refreshCatalog() {
    if (_catalogFlight != null) return _catalogFlight!;
    final generation = _cacheGeneration;
    final flight = () async {
      final list = await _api.stationList();
      if (list is! Map || list['Items'] is! List) throw const ApiException('站点列表格式异常');
      final dictionary = parseDictionary(await _api.dictionary());
      final entries = (list['Items'] as List).map((e) =>
        StationEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      final catalog = StationCatalog(stations: resolveStations(entries, dictionary),
        dictionary: dictionary, updatedAt: _clock().toUtc());
      if (generation == _cacheGeneration) {
        await preferences.setString(catalogCacheKey, jsonEncode({
          'updatedAt': catalog.updatedAt.toIso8601String(), 'dictionary': dictionary,
          'entries': entries.map((e) => e.toJson()).toList()}));
        _catalog = catalog;
        if (!_catalogUpdates.isClosed) _catalogUpdates.add(catalog);
      }
      return catalog;
    }();
    _catalogFlight = flight;
    unawaited(flight.then<void>((_) { _catalogFlight = null; },
      onError: (Object _, StackTrace _) { _catalogFlight = null; }));
    return flight;
  }

  ArrivalSnapshot? cachedArrival(int stationId) => _arrivalCache[stationId];

  Future<ArrivalSnapshot> arrivals(int stationId) async {
    final catalog = await loadCatalog();
    if (!catalog.dictionary.values.contains(stationId)) {
      throw const ApiException('无效的站点 ID，请从站点列表重新选择');
    }
    final running = _arrivalFlights[stationId];
    if (running != null) return running;
    final last = _lastAttempt[stationId];
    if (last != null && _clock().toUtc().difference(last) < const Duration(seconds: 60)) {
      final error = _arrivalErrors[stationId];
      if (error != null) throw error;
      final cached = _arrivalCache[stationId];
      if (cached != null) return cached;
      throw const ApiException('请求过于频繁，请稍后再试');
    }
    final completer = Completer<ArrivalSnapshot>();
    _arrivalFlights[stationId] = completer.future;
    _arrivalQueue = _arrivalQueue.then((_) async {
      _lastAttempt[stationId] = _clock().toUtc();
      try {
        final data = await _api.schedule(stationId);
        if (data is! List) throw const ApiException('到站数据格式异常');
        final fetchedAt = _clock().toUtc();
        final directions = data.map((e) => ArrivalDirection.fromJson(
          Map<String, dynamic>.from(e as Map), observedAt: fetchedAt)).toList();
        if (directions.any((d) => d.stationId != stationId)) {
          throw const ApiException('到站数据与所选站点不符');
        }
        final snapshot = ArrivalSnapshot(stationId: stationId,
          directions: directions, fetchedAt: fetchedAt).retainDwellingFrom(_arrivalCache[stationId]);
        _arrivalCache[stationId] = snapshot;
        _arrivalErrors.remove(stationId);
        completer.complete(snapshot);
      } catch (error, stack) {
        _arrivalErrors[stationId] = error;
        completer.completeError(error, stack);
      } finally { _arrivalFlights.remove(stationId); }
    });
    return completer.future;
  }

  Future<void> clearCatalogCache() async {
    _cacheGeneration++;
    _catalog = null;
    _arrivalCache.clear();
    // Keep request timestamps/errors so clearing cache cannot bypass the rate limit.
    await preferences.remove(catalogCacheKey);
  }

  void dispose() { _catalogUpdates.close(); }
}
