import 'package:material_ui/material_ui.dart';

import '../../app/theme/line_colors.dart';

class LineBadge extends StatelessWidget {
  const LineBadge({super.key, required this.lineId, this.small = false});

  final int lineId;
  final bool small;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$lineId号线',
    child: ExcludeSemantics(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: 5),
        decoration: BoxDecoration(
          color: LineColors.colorOf(lineId),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          '$lineId号线',
          style: (small ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)
              ?.copyWith(color: LineColors.onColorOf(lineId), fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}
