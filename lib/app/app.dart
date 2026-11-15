import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class YongguiApp extends ConsumerStatefulWidget {
  const YongguiApp({super.key});

  @override
  ConsumerState<YongguiApp> createState() => _YongguiAppState();
}

class _YongguiAppState extends ConsumerState<YongguiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(lifecycleProvider.notifier).state = state;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return DynamicColorBuilder(builder: (light, dark) => MaterialApp.router(
      title: '甬轨通',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light,
        dynamicScheme: settings.dynamicColor ? light : null),
      darkTheme: AppTheme.build(Brightness.dark,
        dynamicScheme: settings.dynamicColor ? dark : null),
      themeMode: settings.themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: appRouter,
    ));
  }
}
