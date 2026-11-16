import 'package:material_ui/material_ui.dart';

import '../models/arrival.dart';
import '../utils/time_utils.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Minutes until arrival as "3 分钟" with a large number, or "即将到站" within one minute.
class CountdownText extends StatelessWidget {
  const CountdownText({super.key, required this.remaining, this.large = true});

  final Duration remaining;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme.primary;
    final label = TimeUtils.countdown(remaining);
    final soon = remaining.inMilliseconds <= 60000;
    final number = large ? text.headlineMedium : text.titleLarge;
    final unit = large ? text.titleSmall : text.labelMedium;
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: soon
          ? Text('即将到站', key: const ValueKey('soon'),
              style: (large ? text.titleLarge : text.titleMedium)?.copyWith(color: color, fontWeight: FontWeight.w600))
          : Text.rich(key: ValueKey(label), TextSpan(children: [
              TextSpan(text: '${(remaining.inMilliseconds / 60000).ceil()}',
                style: number?.copyWith(color: color, fontWeight: FontWeight.w600, fontFeatures: _tabular)),
              TextSpan(text: ' 分钟', style: unit?.copyWith(color: color)),
            ])),
      )),
    );
  }
}

/// A later run of one direction: scheduled time, train sequence and countdown.
class ArrivalTile extends StatelessWidget {
  const ArrivalTile({super.key, required this.lineId, required this.run, required this.now});

  final int lineId;
  final ArrivalRun run;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final remaining = TimeUtils.remaining(run.intimeStr, now, intimeDura: run.intimeDura);
    if (remaining == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final countdown = TimeUtils.countdown(remaining);
    return Semantics(
      label: '$lineId号线，到站时刻 ${run.intimeStr}，$countdown，第${run.sequence}班',
      child: ExcludeSemantics(child: SizedBox(
        height: 36,
        child: Row(children: [
          Text(run.intimeStr, style: text.bodyLarge?.copyWith(fontFeatures: _tabular)),
          const SizedBox(width: 8),
          Text('第${run.sequence}班', style: text.labelSmall?.copyWith(color: muted)),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(countdown, key: ValueKey(countdown),
              style: text.bodyMedium?.copyWith(color: muted, fontFeatures: _tabular)),
          ),
        ]),
      )),
    );
  }
}
