import 'package:material_ui/material_ui.dart';

abstract final class LineColors {
  static const ids = <int>[1, 2, 3, 4, 5, 6, 7, 8, 12];
  static const _colors = <int, Color>{
    1: Color(0xFF138FC9),
    2: Color(0xFFD60B17),
    3: Color(0xFFEAAE1A),
    4: Color(0xFF80B82B),
    5: Color(0xFF091F8F),
    6: Color(0xFF197C39),
    7: Color(0xFF794F47),
    8: Color(0xFFE61477),
    12: Color(0xFF45BDCE),
  };

  static Color colorOf(int lineId) => _colors[lineId] ?? const Color(0xFF0B6E8F);

  static Color onColorOf(int lineId) {
    final luminance = colorOf(lineId).computeLuminance();
    final whiteContrast = 1.05 / (luminance + 0.05);
    final blackContrast = (luminance + 0.05) / 0.05;
    return blackContrast >= whiteContrast ? Colors.black : Colors.white;
  }
}
