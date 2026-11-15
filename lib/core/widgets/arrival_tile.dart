import 'package:material_ui/material_ui.dart';

import '../models/arrival.dart';
import '../../app/theme/line_colors.dart';
import '../utils/time_utils.dart';
import 'line_badge.dart';

class ArrivalTile extends StatelessWidget {
  const ArrivalTile({super.key, required this.lineId, required this.run, required this.now});

  final int lineId;
  final ArrivalRun run;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final remaining = TimeUtils.remaining(run.intimeStr, now, intimeDura: run.intimeDura);
    if (remaining == null) return const SizedBox.shrink();
    final countdown = TimeUtils.countdown(remaining);
    return Semantics(
      label: '$lineId号线，到站时刻 ${run.intimeStr}，$countdown，第${run.sequence}班',
      child: ExcludeSemantics(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: IntrinsicHeight(
            child: Row(children: [
              Container(width: 5, color: LineColors.colorOf(lineId)),
              Expanded(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    LineBadge(lineId: lineId, small: true),
                    Text('第 ${run.sequence} 班', style: Theme.of(context).textTheme.labelMedium),
                  ]),
                  const SizedBox(height: 12),
                  Text(run.intimeStr, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()], fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(countdown, key: ValueKey(countdown), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                  ),
                ]),
              )),
            ]),
          ),
        ),
      ),
    );
  }
}
