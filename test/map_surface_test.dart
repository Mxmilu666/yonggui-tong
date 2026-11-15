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
import 'package:yonggui_tong/features/map/map_page.dart';
import 'package:yonggui_tong/features/map/network_painter.dart';
import 'package:yonggui_tong/features/stations/station_page.dart';

class _Catalog extends CatalogController {
  _Catalog(this.catalog);
  final StationCatalog catalog;
  @override
  Future<StationCatalog> build() async => catalog;
}

class _Arrivals extends ArrivalsController {
  _Arrivals(this.snapshot);
  final ArrivalSnapshot snapshot;
  @override
  ArrivalState build(int arg) => ArrivalState(snapshot: snapshot);
}

void main() {
  testWidgets('320dp 线网筛选、缩放、复位、点站进入真实站点详情', (tester) async {
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final list = jsonDecode(File('test/fixtures/stations.json').readAsStringSync()) as Map;
    final dict = parseDictionary((jsonDecode(File('test/fixtures/dict.json').readAsStringSync()) as Map)['Data']);
    final catalog = StationCatalog(
      stations: resolveStations((list['Data']['Items'] as List).map((e) =>
        StationEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList(), dict),
      dictionary: dict, updatedAt: DateTime.utc(2026, 11, 16));
    final graph = MetroNetwork.fromJson(jsonDecode(File('assets/data/network.json').readAsStringSync()) as Map<String, dynamic>);
    final now = DateTime.utc(2026, 11, 16);
    final gulou = catalog.search('鼓楼').single;
    final raw = jsonDecode(File('test/fixtures/gulou.json').readAsStringSync()) as Map;
    final snapshot = ArrivalSnapshot(stationId: gulou.id,
      directions: (raw['Data'] as List).map((e) => ArrivalDirection.fromJson(
        Map<String, dynamic>.from(e as Map), observedAt: now)).toList(), fetchedAt: now);
    final router = GoRouter(initialLocation: '/map', routes: [
      GoRoute(path: '/map', builder: (_, _) => const MapPage()),
      GoRoute(path: '/stations/:id', builder: (_, state) => StationPage(
        stationId: int.parse(state.pathParameters['id']!))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      preferencesProvider.overrideWithValue(preferences),
      catalogProvider.overrideWith(() => _Catalog(catalog)),
      networkProvider.overrideWith((ref) async => graph),
      arrivalsProvider.overrideWith(() => _Arrivals(snapshot)),
      nowProvider.overrideWith((ref) => Stream.value(now)),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final initial = viewer.transformationController!.value.clone();
    await tester.tap(find.widgetWithText(FilterChip, '1号线'));
    await tester.pumpAndSettle();
    final painter = tester.widget<CustomPaint>(find.byWidgetPredicate((w) =>
      w is CustomPaint && w.painter is NetworkPainter)).painter! as NetworkPainter;
    expect(painter.selectedLine, 1);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final left = await tester.startGesture(center - const Offset(30, 0), pointer: 1);
    final right = await tester.startGesture(center + const Offset(30, 0), pointer: 2);
    await tester.pump();
    await left.moveTo(center - const Offset(70, 0));
    await right.moveTo(center + const Offset(70, 0));
    await tester.pump();
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value.entry(0, 0), greaterThan(initial.entry(0, 0)),
      reason: '首次缩放必须从实际2D比例开始，不能误读z轴的1');
    await tester.tap(find.byTooltip('重置视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('放大线网'));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value.entry(0, 0), greaterThan(initial.entry(0, 0)));
    await tester.tap(find.byTooltip('重置视图'));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value, initial);
    final world = graph.points[gulou.id]!.position;
    final position = MatrixUtils.transformPoint(initial, world) + tester.getTopLeft(find.byType(InteractiveViewer));
    await tester.tapAt(position);
    await tester.pumpAndSettle();
    expect(find.text('鼓楼'), findsOneWidget);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(tester.widget<StationPage>(find.byType(StationPage)).stationId, gulou.id);
    expect(find.text('站点编码 0110 / 0242'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
