import 'package:material_ui/material_ui.dart';

abstract final class AppTheme {
  static const seed = Color(0xFF0B6E8F);

  static ThemeData build(Brightness brightness, {ColorScheme? dynamicScheme}) {
    final scheme = dynamicScheme ?? ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: 'YongguiSans',
      fontFamilyFallback: const ['PingFang SC', 'Noto Sans CJK SC', 'sans-serif'],
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(centerTitle: false),
      // Shape is left to each variant so Card.outlined keeps its MD3 border.
      cardTheme: const CardThemeData(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    );
  }
}
