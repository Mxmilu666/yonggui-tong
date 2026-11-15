import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yonggui_tong/core/api/api_exception.dart';
import 'package:yonggui_tong/core/models/arrival.dart';
import 'package:yonggui_tong/core/models/station.dart';
import 'package:yonggui_tong/core/utils/station_resolver.dart';
import 'package:yonggui_tong/core/utils/time_utils.dart';
import 'package:yonggui_tong/data/repositories/metro_repository.dart';
import 'package:yonggui_tong/data/repositories/favorites_repository.dart';
import 'package:yonggui_tong/data/providers.dart';

Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());
Map<String, int> dictionary() => parseDictionary((fixture('dict') as Map)['Data']);
List<StationEntry> stationEntries() => ((fixture('stations') as Map)['Data']['Items'] as List)
    .map((e) => StationEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();

class FixtureAdapter implements HttpClientAdapter {
  final paths = <String>[];
  int failures = 0;
  int active = 0, maximumActive = 0;
  int? statusCode;
  DioExceptionType? failureType;
  Object? scheduleData;
  Completer<void>? gate;
  Completer<void>? started;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    paths.add(options.path);
    if (started case final signal? when !signal.isCompleted) signal.complete();
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      if (gate != null) await gate!.future;
      if (failureType != null) throw DioException(requestOptions: options, type: failureType!);
      if (statusCode != null) {
        return ResponseBody.fromString('{}', statusCode!,
          headers: {Headers.contentTypeHeader: ['application/json']});
      }
      if (failures > 0) {
        failures--;
        throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
      }
      final name = options.path.endsWith('StationList') ? 'stations'
        : options.path.endsWith('Dict') ? 'dict' : 'gulou';
      final body = options.path.contains('ScheduleTime') && scheduleData != null
        ? {'Code': 200, 'Data': scheduleData, 'Message': ''} : fixture(name);
      return ResponseBody.fromString(jsonEncode(body), 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
    } finally { active--; }
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late FixtureAdapter adapter;
  late DateTime now;
  late MetroRepository repository;
  late List<Duration> delays;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    adapter = FixtureAdapter();
    now = DateTime.utc(2026, 11, 15, 18);
    delays = [];
    final dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid'))..httpClientAdapter = adapter;
    repository = MetroRepository(preferences: prefs, dio: dio, clock: () => now,
      delay: (duration) async { delays.add(duration); });
  });
  tearDown(() { repository.dispose(); });

  test('double decoded Dict merges Gulou by integer ID and retains extension line', () {
    final dict = dictionary();
    expect(dict['0110'], 16);
    expect(dict['0242'], 16);
    final stations = resolveStations(stationEntries(), dict);
    final gulou = stations.singleWhere((s) => s.id == 16);
    expect(gulou.codes, containsAll(['0110', '0242']));
    expect(gulou.lineIds, [1, 2]);
    expect(stations.singleWhere((s) => s.codes.contains('3151')).lineIds, [3]);
    expect(lineIdOf('1201'), 12);
    expect(() => lineIdOf('3101'), throwsFormatException);
    expect(gulou.matches('GULOU'), isTrue);
    final catalog = StationCatalog(stations: stations, dictionary: dict, updatedAt: now);
    for (final query in ['1号线', '1号线路', '地铁1号线', 'line 1', '1']) {
      expect(catalog.search(query).map((s) => s.id),
        catalog.stationsForLine(1).map((s) => s.id));
    }
    expect(catalog.search('0110').single.id, 16);
    expect(catalog.stationsForLine(3).first.name, '金海路');
    expect(catalog.stationsForLine(3)[9].name, '高塘桥');
    expect(catalog.stationsForLine(3).last.name, '大通桥');
    expect(catalog.stationsForLine(12).first.name, '大目湾');
  });

  test('countdown uses Beijing wall time, rejects past and accepts narrow midnight rollover', () {
    final instant = DateTime.parse('2026-11-16T00:00:00+08:00');
    expect(TimeUtils.remaining('00:01:01', instant, intimeDura: 61), const Duration(seconds: 61));
    expect(TimeUtils.remaining('00:01:01', instant.toLocal(), intimeDura: 61), const Duration(seconds: 61));
    expect(TimeUtils.remaining('00:01:00', DateTime.parse('2026-11-15T23:59:00+08:00'),
      intimeDura: 120), const Duration(minutes: 2));
    expect(TimeUtils.remaining('09:59:59', DateTime.parse('2026-11-16T10:00:00+08:00'),
      intimeDura: 1), isNull);
    expect(TimeUtils.remaining('08:00:00', instant, intimeDura: 1), isNull);
    expect(TimeUtils.remaining('25:01:00', instant, intimeDura: 1), isNull);
    expect(TimeUtils.remaining('00:01:00', instant, intimeDura: -60), isNull);
    expect(TimeUtils.countdown(const Duration(seconds: 60)), '即将到站');
    expect(TimeUtils.countdown(const Duration(seconds: 61)), '2 分钟后');
  });

  test('four real Gulou direction blocks survive sentinel filtering', () {
    final directions = ((fixture('gulou') as Map)['Data'] as List).map((e) =>
      ArrivalDirection.fromJson(Map<String, dynamic>.from(e as Map), observedAt: now)).toList();
    expect(directions.length, 4);
    expect(directions.map((d) => '${d.lineId}_${d.flag}'), ['1_1', '1_2', '2_1', '2_2']);
    expect(directions.every((d) => d.runs.isNotEmpty && d.validRuns(now).isEmpty), isTrue);
  });

  test('cached timetable never reappears the next day', () {
    final direction = ArrivalDirection(lineId: 1, flag: 1, stationId: 16,
      observedAt: DateTime.parse('2026-11-15T10:00:00+08:00'), runs: [
        const ArrivalRun(sequence: 1, intimeStr: '10:03:00', outTimeStr: '10:03:20', intimeDura: 180)]);
    expect(direction.validRuns(DateTime.parse('2026-11-16T10:01:00+08:00')), isEmpty);
  });

  test('catalog persists, stays fresh for 24 hours, then cached-first refreshes', () async {
    final catalog = await repository.loadCatalog();
    expect(catalog.stationById(16)!.lineIds, [1, 2]);
    expect(adapter.paths.length, 2);
    final secondAdapter = FixtureAdapter();
    final second = MetroRepository(preferences: prefs,
      dio: Dio(BaseOptions(baseUrl: 'https://fixture.invalid'))..httpClientAdapter = secondAdapter,
      clock: () => now, delay: (_) async {});
    addTearDown(second.dispose);
    expect((await second.loadCatalog()).stationById(16)!.name, '鼓楼');
    expect(secondAdapter.paths, isEmpty);
    now = now.add(const Duration(hours: 25));
    final updated = second.catalogUpdates.first;
    expect((await second.loadCatalog()).updatedAt, catalog.updatedAt);
    expect((await updated).updatedAt, now);
    expect(secondAdapter.paths.length, 2);
  });

  test('transient failures retry twice with exponential delay; permanent error surfaces', () async {
    adapter.failures = 2;
    await repository.loadCatalog();
    expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    adapter.failures = 3;
    await expectLater(repository.loadCatalog(force: true), throwsA(isA<ApiException>()));
    expect((await repository.cachedCatalog())!.stationById(16), isNotNull);
  });

  for (final status in [404, 500]) {
    test('HTTP $status 保留旧到站并报告明确错误', () async {
      final old = await repository.arrivals(16);
      now = now.add(const Duration(seconds: 60));
      adapter.statusCode = status;
      await expectLater(repository.arrivals(16), throwsA(isA<ApiException>()
        .having((error) => error.message, 'HTTP状态', contains('$status'))));
      expect(repository.cachedArrival(16), same(old));
    });
  }

  test('超时结束重试后反馈，Data空数组是成功空状态而非网络错误', () async {
    await repository.loadCatalog();
    adapter.failureType = DioExceptionType.receiveTimeout;
    await expectLater(repository.arrivals(16), throwsA(isA<ApiException>()
      .having((error) => error.message, '超时提示', contains('超时'))));
    adapter.failureType = null;
    adapter.scheduleData = [];
    now = now.add(const Duration(seconds: 60));
    expect((await repository.arrivals(16)).directions, isEmpty);
    expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
  });

  test('arrivals deduplicate in flight and rate limit manual refresh across reentry', () async {
    await repository.loadCatalog();
    adapter.gate = Completer<void>();
    final first = repository.arrivals(16);
    final second = repository.arrivals(16);
    await Future<void>.delayed(Duration.zero);
    adapter.gate!.complete();
    final results = await Future.wait([first, second]);
    expect(identical(results.first, results.last), isTrue);
    expect(adapter.paths.where((p) => p.contains('ScheduleTime')), ['/Api/Stations/ScheduleTime/16']);
    await repository.arrivals(16);
    expect(adapter.paths.length, 3);
    now = now.add(const Duration(seconds: 60));
    await repository.arrivals(16);
    expect(adapter.paths.length, 4);
    await expectLater(repository.arrivals(999999), throwsA(isA<ApiException>()));
  });

  test('failure preserves old snapshot and cannot hammer backend within one minute', () async {
    await repository.loadCatalog();
    final old = await repository.arrivals(16);
    now = now.add(const Duration(seconds: 60));
    adapter.failures = 3;
    await expectLater(repository.arrivals(16), throwsA(isA<ApiException>()));
    final count = adapter.paths.length;
    await expectLater(repository.arrivals(16), throwsA(isA<ApiException>()));
    expect(adapter.paths.length, count);
    expect(identical(repository.cachedArrival(16), old), isTrue);
  });

  test('arrival queue serializes different stations, including error completion', () async {
    await repository.loadCatalog();
    adapter.gate = Completer<void>();
    adapter.started = Completer<void>();
    final first = repository.arrivals(16);
    // Fixture returns Gulou; another valid station must report mismatch, not fake its data.
    final other = repository.arrivals(7);
    final rejected = expectLater(other, throwsA(isA<ApiException>()));
    await adapter.started!.future;
    expect(adapter.paths.where((p) => p.contains('ScheduleTime')).length, 1);
    adapter.gate!.complete();
    await first;
    await rejected;
    expect(adapter.maximumActive, 1);
  });

  test('clearing caches leaves favorites and settings untouched', () async {
    await repository.loadCatalog();
    await FavoritesRepository(prefs).save({16});
    await prefs.setInt('settings.refresh', 120);
    await repository.clearCatalogCache();
    expect(prefs.getString(MetroRepository.catalogCacheKey), isNull);
    expect(FavoritesRepository(prefs).load(), {16});
    expect(prefs.getInt('settings.refresh'), 120);
  });

  test('favorites and all settings survive provider recreation', () async {
    final container = ProviderContainer(overrides: [preferencesProvider.overrideWithValue(prefs)]);
    expect(container.read(settingsProvider).dynamicColor, isFalse);
    await container.read(favoritesProvider.notifier).toggle(16);
    await container.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
    await container.read(settingsProvider.notifier).setDynamicColor(true);
    await container.read(settingsProvider.notifier).setRefreshSeconds(120);
    container.dispose();
    final restored = ProviderContainer(overrides: [preferencesProvider.overrideWithValue(prefs)]);
    addTearDown(restored.dispose);
    expect(restored.read(favoritesProvider), {16});
    expect(restored.read(settingsProvider).themeMode, ThemeMode.dark);
    expect(restored.read(settingsProvider).dynamicColor, isTrue);
    expect(restored.read(settingsProvider).refreshSeconds, 120);
  });
}
