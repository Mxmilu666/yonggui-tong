import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yonggui_tong/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('收藏路线功能完整流程', (tester) async {
    SharedPreferences.setMockInitialValues({});
    
    await app.main();
    await tester.pumpAndSettle();

    // 进入行程估算页
    await tester.tap(find.text('选起终点，估算行程'));
    await tester.pumpAndSettle();

    // 选择起点
    await tester.tap(find.text('起点').first);
    await tester.pumpAndSettle();
    
    await tester.enterText(find.byType(TextField).last, 'gulou');
    await tester.pumpAndSettle();
    
    await tester.tap(find.text('鼓楼').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 选择终点  
    await tester.tap(find.text('终点').first);
    await tester.pumpAndSettle();
    
    await tester.enterText(find.byType(TextField).last, 'huochezhan');
    await tester.pumpAndSettle();
    
    await tester.tap(find.text('宁波火车站').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 应该看到路线结果
    expect(find.textContaining('分钟'), findsOneWidget);
    
    // 点击收藏按钮
    final favoriteButton = find.byIcon(Icons.favorite_border);
    expect(favoriteButton, findsOneWidget);
    
    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();

    // 验证图标变化
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    
    // 回到首页
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // 应该看到收藏路线卡片
    expect(find.text('收藏路线'), findsOneWidget);
    expect(find.textContaining('鼓楼 → 宁波火车站'), findsOneWidget);
    
    print('✅ 路线收藏功能测试通过');
  });
}
