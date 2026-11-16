import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../models/arrival.dart';
import '../utils/time_utils.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Arrival countdown, or "停靠中" from arrival until the published departure.
class CountdownText extends ConsumerWidget {
  const CountdownText({super.key, required this.remaining, this.large = true});

  final Duration remaining;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showSeconds = ref.watch(settingsProvider.select((s) => s.arrivalSeconds));
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme.primary;
    final label = TimeUtils.countdown(remaining, showSeconds: showSeconds);
    final simpleLabel = showSeconds || remaining.inMilliseconds <= 60000;
    final number = large ? text.headlineMedium : text.titleLarge;
    final unit = large ? text.titleSmall : text.labelMedium;
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: simpleLabel
          ? Text(label, key: ValueKey(label),
              style: (large ? text.titleLarge : text.titleMedium)?.copyWith(
                color: color, fontWeight: FontWeight.w600, fontFeatures: _tabular))
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
class ArrivalTile extends ConsumerWidget {
  const ArrivalTile({super.key, required this.lineId, required this.run, required this.now});

  final int lineId;
  final ScheduledRun run;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showSeconds = ref.watch(settingsProvider.select((s) => s.arrivalSeconds));
    if (!now.isBefore(run.departAt)) return const SizedBox.shrink();
    final remaining = run.arriveAt.difference(now);
    final dwelling = run.isDwelling(now);
    final time = dwelling ? run.run.outTimeStr : run.run.intimeStr;
    final event = dwelling ? '发车' : '到站';
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final countdown = TimeUtils.countdown(remaining, showSeconds: showSeconds);
    return Semantics(
      label: '$lineId号线，$event时刻 $time，$countdown，第${run.run.sequence}班',
      child: ExcludeSemantics(child: SizedBox(
        height: 36,
        child: Row(children: [
          Text('$time${dwelling ? ' 发车' : ''}', style: text.bodyLarge?.copyWith(fontFeatures: _tabular)),
          const SizedBox(width: 8),
          Text('第${run.run.sequence}班', style: text.labelSmall?.copyWith(color: muted)),
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
