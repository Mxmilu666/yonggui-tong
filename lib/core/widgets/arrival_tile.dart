import 'package:material_ui/material_ui.dart';

import '../models/arrival.dart';
import '../../app/theme/line_colors.dart';
import '../utils/time_utils.dart';

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
    final urgent = remaining.inMinutes <= 3;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      child: Semantics(
        label: '$lineId号线，到站时刻 ${run.intimeStr}，$countdown，第${run.sequence}班',
        child: ExcludeSemantics(
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(width: 6, color: LineColors.colorOf(lineId))),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(run.intimeStr, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w600,
                  color: urgent ? Theme.of(context).colorScheme.error : null,
                )),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(urgent ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                    size: 16, color: urgent ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Flexible(child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(countdown, key: ValueKey(countdown),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: urgent ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: urgent ? FontWeight.w600 : null,
                      )))),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: LineColors.colorOf(lineId).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$lineId号线', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: LineColors.colorOf(lineId),
                    fontWeight: FontWeight.w600,
                  )),
                ),
                const SizedBox(height: 6),
                Text('第${run.sequence}班', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
