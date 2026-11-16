import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yonggui_tong/app/app.dart';
import 'package:yonggui_tong/data/repositories/favorites_repository.dart';
import 'package:yonggui_tong/app/router.dart';
import 'package:yonggui_tong/data/providers.dart';
import 'package:yonggui_tong/features/arrivals/arrivals_page.dart';
import 'package:yonggui_tong/features/map/map_page.dart';
import 'package:yonggui_tong/features/map/network_painter.dart';
import 'package:yonggui_tong/features/planner/planner_page.dart';
import 'package:yonggui_tong/core/models/line.dart';
import 'package:yonggui_tong/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 API 全流程：鼓楼四方向、60秒刷新、线网、估算、主题设置', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(YongguiApp));
    final container = ProviderScope.containerOf(context);
    final catalog = await container.read(catalogProvider.future);
    final gulou = catalog.search('鼓楼').single;
    expect(gulou.codes, containsAll(['0110', '0242']));
    expect(catalog.dictionary['0110'], gulou.id);
    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'gulou');
    await tester.pumpAndSettle();
    await tester.tap(find.text('鼓楼').last);
    await tester.pumpAndSettle();
    expect(find.byType(ArrivalsPage), findsOneWidget);
    await container.read(arrivalsProvider(gulou.id).notifier).refresh();
    await tester.pumpAndSettle();
    final result = container.read(arrivalsProvider(gulou.id));
    expect(result.error, isNull);
    expect(result.snapshot!.directions.map((d) => '${d.lineId}_${d.flag}'),
      ['1_1', '1_2', '2_1', '2_2']);
    final previous = container.read(favoritesProvider).contains(gulou.id);
    await tester.tap(find.byTooltip(previous ? '取消收藏' : '收藏车站'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList(FavoritesRepository.storageKey)?.contains('${gulou.id}'), !previous);
    final snapshot = result.snapshot;
    container.read(lifecycleProvider.notifier).state = AppLifecycleState.paused;
    container.read(lifecycleProvider.notifier).state = AppLifecycleState.resumed;
    await tester.pumpAndSettle();
    expect(container.read(arrivalsProvider(gulou.id)).snapshot, same(snapshot));
    // Let the actual production timer and server run for a full poll interval.
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 80));
      while (container.read(arrivalsProvider(gulou.id)).snapshot!.fetchedAt == snapshot!.fetchedAt) {
        if (DateTime.now().isAfter(deadline)) fail('60秒前台轮询没有更新到站数据');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    });
    await tester.pumpAndSettle();
    expect(container.read(arrivalsProvider(gulou.id)).snapshot!.fetchedAt.isAfter(snapshot!.fetchedAt), isTrue);
    appRouter.go('/map');
    await tester.pumpAndSettle();
    expect(find.byType(MapPage), findsOneWidget);
    await container.read(networkProvider.future);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '1号线'));
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final before = viewer.transformationController!.value.entry(0, 0);
    await tester.tap(find.byTooltip('放大线网'));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value.entry(0, 0), greaterThan(before));
    final paint = tester.widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is NetworkPainter));
    expect((paint.painter! as NetworkPainter).selectedLine, 1);
    await tester.tap(find.byTooltip('重置视图'));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value.entry(0, 0), before);
    final origin = catalog.search('东门口（天一广场）').single;
    final destination = catalog.search('城隍庙').single;
    appRouter.push('/planner?from=${origin.id}&to=${destination.id}');
    await tester.pumpAndSettle();
    expect(find.byType(PlannerPage), findsOneWidget);
    expect(find.text('8 分钟'), findsOneWidget);
    expect(find.text('2 站 · 1 次换乘'), findsOneWidget);
    appRouter.go('/settings');
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('外观'))).brightness, Brightness.dark);
    await tester.scrollUntilVisible(find.text('每 120 秒'), 250,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('每 120 秒'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).refreshSeconds, 120);
    expect(preferences.getInt('settings.refresh'), 120);
    // Restore the conservative shipping defaults for the emulator preview.
    await container.read(settingsProvider.notifier).setThemeMode(ThemeMode.system);
    await container.read(settingsProvider.notifier).setRefreshSeconds(60);
  });
}
