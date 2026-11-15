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
import 'package:yonggui_tong/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 API 搜索鼓楼，四方向、收藏、前后台与本地设置', (tester) async {
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
    appRouter.go('/settings');
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
  });
}
