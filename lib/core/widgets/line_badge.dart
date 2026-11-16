import 'package:material_ui/material_ui.dart';

import '../../app/theme/line_colors.dart';

/// Line identity pill: line color fill, contrast-checked label, no shadow.
class LineBadge extends StatelessWidget {
  const LineBadge({super.key, required this.lineId, this.small = false});

  final int lineId;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$lineId号线',
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 4),
          decoration: ShapeDecoration(color: LineColors.colorOf(lineId), shape: const StadiumBorder()),
          child: Text('$lineId号线', style: (small ? text.labelSmall : text.labelMedium)
            ?.copyWith(color: LineColors.onColorOf(lineId), fontWeight: FontWeight.w600, height: 1.2)),
        ),
      ),
    );
  }
}

/// Circular line number, for lists and grids where the label is already "N号线".
class LineAvatar extends StatelessWidget {
  const LineAvatar({super.key, required this.lineId, this.size = 32});

  final int lineId;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: LineColors.colorOf(lineId), shape: BoxShape.circle),
      child: Text('$lineId', style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: LineColors.onColorOf(lineId), fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()])),
    ),
  );
}
