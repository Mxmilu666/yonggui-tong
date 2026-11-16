import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yonggui_tong/core/models/arrival.dart';
import 'package:yonggui_tong/core/models/line.dart';
import 'package:yonggui_tong/core/models/station.dart';
import 'package:yonggui_tong/core/utils/station_resolver.dart';
import 'package:yonggui_tong/data/providers.dart';
import 'package:yonggui_tong/features/arrivals/arrivals_page.dart';
import 'package:yonggui_tong/features/home/home_page.dart';
import 'package:yonggui_tong/features/settings/settings_page.dart';
import 'package:yonggui_tong/features/planner/planner_page.dart';
import 'package:yonggui_tong/app/router.dart';
import 'package:yonggui_tong/app/version.dart';
import 'package:yonggui_tong/core/models/favorite_route.dart';
import 'package:yonggui_tong/data/repositories/favorites_repository.dart';
import 'package:yonggui_tong/features/home/favorite_route_card.dart';

class _FixtureCatalog extends CatalogController {
  _FixtureCatalog(this.catalog);
  final StationCatalog catalog;
  @override
  Future<StationCatalog> build() async => catalog;
}

class _FixtureArrivals extends ArrivalsController {
  _FixtureArrivals(this.snapshot);
  final ArrivalSnapshot snapshot;
  @override
  ArrivalState build(int arg) => ArrivalState(snapshot: snapshot);
  @override
  Future<void> refresh() async {}
}

void main() {
  late StationCatalog catalog;
  late ArrivalSnapshot snapshot;
  late SharedPreferences preferences;
  final now = DateTime.utc(2026, 11, 15, 17, 27);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    final stationJson = jsonDecode(File('test/fixtures/stations.json').readAsStringSync()) as Map<String, dynamic>;
    final dictJson = jsonDecode(File('test/fixtures/dict.json').readAsStringSync()) as Map<String, dynamic>;
    final dictionary = parseDictionary(dictJson['Data']);
    final entries = ((stationJson['Data'] as Map)['Items'] as List)
        .map((item) => StationEntry.fromJson(Map<String, dynamic>.from(item as Map))).toList();
    catalog = StationCatalog(stations: resolveStations(entries, dictionary), dictionary: dictionary, updatedAt: now);
    final arrivalJson = jsonDecode(File('test/fixtures/gulou.json').readAsStringSync()) as Map<String, dynamic>;
    snapshot = ArrivalSnapshot(
      stationId: catalog.stations.singleWhere((station) => station.name == '鼓楼').id,
      directions: (arrivalJson['Data'] as List).map((item) => ArrivalDirection.fromJson(Map<String, dynamic>.from(item as Map), observedAt: now)).toList(),
      fetchedAt: now,
    );
  });

  Widget scope(Widget child) => ProviderScope(overrides: [
    preferencesProvider.overrideWithValue(preferences),
    catalogProvider.overrideWith(() => _FixtureCatalog(catalog)),
    arrivalsProvider.overrideWith(() => _FixtureArrivals(snapshot)),
    nowProvider.overrideWith((ref) => Stream.value(now)),
    networkProvider.overrideWith((ref) async => MetroNetwork.fromJson(
      jsonDecode(File('assets/data/network.json').readAsStringSync()) as Map<String, dynamic>)),
  ], child: child);

  testWidgets('首页和到站详情在停靠期间保留当前车，离站后才切换', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gulou = catalog.search('鼓楼').single;
    await preferences.setStringList('metro.favorites.v1', ['${gulou.id}']);
    snapshot = ArrivalSnapshot(stationId: gulou.id, fetchedAt: now, directions: [
      ArrivalDirection(lineId: 1, flag: 1, stationId: gulou.id, observedAt: now, runs: [
        const ArrivalRun(sequence: 1, intimeStr: '01:26:50', outTimeStr: '01:27:35', intimeDura: -10, outTimeDura: 35),
        const ArrivalRun(sequence: 2, intimeStr: '01:31:00', outTimeStr: '01:31:45', intimeDura: 240, outTimeDura: 285),
      ]),
    ]);
    await tester.pumpWidget(scope(MaterialApp(home: const HomePage())));
    await tester.pumpAndSettle();
    expect(find.text('停靠中'), findsOneWidget);
    expect(find.text('01:27 发车'), findsOneWidget);
    expect(find.text('01:31'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    final clock = StreamController<DateTime>.broadcast();
    addTearDown(clock.close);
    await tester.pumpWidget(ProviderScope(overrides: [
      preferencesProvider.overrideWithValue(preferences),
      catalogProvider.overrideWith(() => _FixtureCatalog(catalog)),
      arrivalsProvider.overrideWith(() => _FixtureArrivals(snapshot)),
      nowProvider.overrideWith((ref) => clock.stream),
    ], child: MaterialApp(home: ArrivalsPage(stationId: gulou.id))));
    clock.add(now);
    await tester.pumpAndSettle();
    expect(find.text('停靠中'), findsOneWidget);
    expect(find.text('01:27:35 发车 · 第1班'), findsOneWidget);
    clock.add(now.add(const Duration(seconds: 35)));
    await tester.pumpAndSettle();
    expect(find.text('停靠中'), findsNothing);
    expect(find.text('01:31:00 到站 · 第2班'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('320dp home search routes the real 鼓楼 ID and retains four empty directions', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(path: '/arrivals/:id', builder: (_, state) => ArrivalsPage(stationId: int.parse(state.pathParameters['id']!))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(scope(MaterialApp.router(theme: ThemeData(useMaterial3: true), routerConfig: router)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '鼓楼');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '鼓楼'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/arrivals/16');
    for (final destination in ['霞浦', '高桥西', '红联', '栎社国际机场']) {
      expect(find.text('往 $destination'), findsOneWidget);
    }
    expect(find.text('暂无有效班次'), findsNWidgets(4));
    expect(find.text('01:27:04'), findsNothing);
    expect(find.text('已停运'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('收藏车站'));
    await tester.pumpAndSettle();
    expect(preferences.getStringList('metro.favorites.v1'), contains('16'));
    expect(find.byTooltip('取消收藏'), findsOneWidget);
  });

  testWidgets('arrival board fits beside a desktop navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(scope(MaterialApp(home: Scaffold(body: Row(children: [
      NavigationRail(selectedIndex: 1, destinations: const [
        NavigationRailDestination(icon: Icon(Icons.home_outlined), label: Text('首页')),
        NavigationRailDestination(icon: Icon(Icons.train_outlined), label: Text('到站')),
      ]),
      Expanded(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: ArrivalBoard(stationId: snapshot.stationId)))),
    ])))));
    await tester.pumpAndSettle();
    expect(find.text('暂无有效班次'), findsNWidgets(4));
    for (final destination in ['霞浦', '高桥西', '红联', '栎社国际机场']) {
      expect(find.text('往 $destination'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页下一班使用同一终点名称，不泄露方向编号', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gulou = catalog.search('鼓楼').single;
    await preferences.setStringList('metro.favorites.v1', ['${gulou.id}']);
    snapshot = ArrivalSnapshot(stationId: gulou.id, fetchedAt: now, directions: [
      ArrivalDirection(lineId: 2, flag: 2, stationId: gulou.id, observedAt: now, runs: [
        const ArrivalRun(sequence: 1, intimeStr: '01:29:00', outTimeStr: '01:29:20', intimeDura: 1, outTimeDura: 1),
      ]),
    ]);
    await tester.pumpWidget(scope(MaterialApp(home: const HomePage())));
    await tester.pumpAndSettle();
    expect(find.text('往 栎社国际机场'), findsOneWidget);
    expect(find.text('01:29'), findsOneWidget);
    expect(find.textContaining('方向'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('到站收藏显示下一班，收藏、搜索及直接进入站点后均可返回列表', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gulou = catalog.search('鼓楼').single;
    await preferences.setStringList('metro.favorites.v1', ['${gulou.id}']);
    snapshot = ArrivalSnapshot(stationId: gulou.id, fetchedAt: now, directions: [
      ArrivalDirection(lineId: 1, flag: 1, stationId: gulou.id, observedAt: now, runs: [
        const ArrivalRun(sequence: 1, intimeStr: '01:31:00', outTimeStr: '01:31:30', intimeDura: 1, outTimeDura: 1),
      ]),
    ]);
    appRouter.go('/');
    addTearDown(() => appRouter.go('/'));
    await tester.pumpWidget(scope(MaterialApp.router(routerConfig: appRouter)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('到站'));
    await tester.pumpAndSettle();
    expect(find.text('往 霞浦'), findsOneWidget);
    expect(find.text('01:31'), findsOneWidget);
    await tester.tap(find.text('鼓楼'));
    await tester.pumpAndSettle();
    expect(tester.widget<ArrivalsPage>(find.byType(ArrivalsPage)).stationId, gulou.id);
    expect(find.text('车站详情'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<ArrivalsPage>(find.byType(ArrivalsPage)).stationId, isNull);
    expect(find.text('01:31'), findsOneWidget);

    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '鼓楼');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '鼓楼'));
    await tester.pumpAndSettle();
    expect(tester.widget<ArrivalsPage>(find.byType(ArrivalsPage)).stationId, gulou.id);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<ArrivalsPage>(find.byType(ArrivalsPage)).stationId, isNull);

    appRouter.go('/');
    await tester.pumpAndSettle();
    appRouter.go('/arrivals/${gulou.id}');
    await tester.pumpAndSettle();
    expect(tester.widget<ArrivalsPage>(find.byType(ArrivalsPage)).stationId, gulou.id);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<ArrivalsPage>(find.byType(ArrivalsPage)).stationId, isNull);
    expect(find.text('收藏车站'), findsOneWidget);
    expect(find.text('01:31'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击首页收藏路线卡片，按起终点打开行程估算', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final from = catalog.search('东门口（天一广场）').single;
    final to = catalog.search('城隍庙').single;
    await preferences.setStringList(FavoritesRepository.routesStorageKey, [
      jsonEncode(FavoriteRoute(originId: from.id, destinationId: to.id, name: '东门口 → 城隍庙').toJson()),
    ]);
    await tester.pumpWidget(scope(MaterialApp.router(routerConfig: appRouter)));
    await tester.pumpAndSettle();
    final card = find.byType(FavoriteRouteCard);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    final planner = tester.widget<PlannerPage>(find.byType(PlannerPage));
    expect((planner.originId, planner.destinationId), (from.id, to.id));
    expect(find.text('8 分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 深色行程估算可换站、交换并展示换乘明细', (tester) async {
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final from = catalog.search('东门口（天一广场）').single;
    final to = catalog.search('城隍庙').single;
    await tester.pumpWidget(scope(MaterialApp(theme: ThemeData(
      useMaterial3: true, brightness: Brightness.dark),
      home: PlannerPage(originId: from.id, destinationId: to.id))));
    await tester.pumpAndSettle();
    expect(find.text('8 分钟'), findsOneWidget);
    expect(find.text('2 站 · 1 次换乘'), findsOneWidget);
    await tester.tap(find.byTooltip('交换起点与终点'));
    await tester.pumpAndSettle();
    expect(find.text('8 分钟'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('在 鼓楼 换乘 · 估算 4 分钟'), 250,
      scrollable: find.byType(Scrollable).first);
    expect(find.text('在 鼓楼 换乘 · 估算 4 分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('about page names the data source and fits 320dp with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.4)), child: child!), home: const AboutPage()));
    await tester.pumpAndSettle();
    expect(find.text('宁波地铁出行助手 · $appVersion'), findsOneWidget);
    expect(find.text('数据来自宁波地铁官方'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
