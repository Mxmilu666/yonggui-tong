import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/favorite_route.dart';
import '../../core/models/route_plan.dart';
import '../../core/models/station.dart';
import '../../core/utils/time_utils.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';
import '../planner/planner_page.dart' show routePlannerProvider;

class FavoriteRouteCard extends ConsumerWidget {
  const FavoriteRouteCard({super.key, required this.route});
  final FavoriteRoute route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final planner = ref.watch(routePlannerProvider).valueOrNull;
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now().toUtc();
    
    if (catalog == null || planner == null) {
      return const SizedBox.shrink();
    }

    final origin = catalog.stationById(route.originId);
    final destination = catalog.stationById(route.destinationId);
    if (origin == null || destination == null) {
      return const SizedBox.shrink();
    }

    final plan = planner.estimate(origin.id, destination.id);
    if (plan == null) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final transferWarnings = _checkTransferTiming(plan, catalog, ref, now);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/planner?origin=${route.originId}&destination=${route.destinationId}'),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(width: 6, color: colors.primary)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${origin.name} → ${destination.name}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))),
              Icon(Icons.arrow_forward_rounded, size: 24, color: colors.onSurfaceVariant),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final segment in plan.segments) LineBadge(lineId: segment.lineId, small: true),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.schedule, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('${plan.minutes} 分钟 · ${plan.stops} 站${plan.transfers > 0 ? ' · ${plan.transfers} 次换乘' : ''}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            ]),
            if (transferWarnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...transferWarnings.map((warning) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: colors.error),
                  const SizedBox(width: 6),
                  Expanded(child: Text(warning, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.error, fontWeight: FontWeight.w600))),
                ]),
              )),
            ],
          ]),
        ),
      ),
    );
  }

  List<String> _checkTransferTiming(RoutePlan plan, StationCatalog catalog, WidgetRef ref, DateTime now) {
    final warnings = <String>[];
    if (plan.segments.length < 2) return warnings;

    for (var i = 0; i < plan.segments.length - 1; i++) {
      final transferStationId = plan.segments[i].stationIds.last;
      final station = catalog.stationById(transferStationId);
      if (station == null) continue;

      final arrivalsState = ref.watch(arrivalsProvider(transferStationId));
      final snapshot = arrivalsState.snapshot;
      if (snapshot == null) continue;

      // Find arrivals for current and next line
      final currentLineId = plan.segments[i].lineId;
      final nextLineId = plan.segments[i + 1].lineId;

      final currentArrivals = snapshot.directions
          .where((d) => d.lineId == currentLineId)
          .expand((d) => d.validRuns(now))
          .toList();
      final nextArrivals = snapshot.directions
          .where((d) => d.lineId == nextLineId)
          .expand((d) => d.validRuns(now))
          .toList();

      if (currentArrivals.isEmpty || nextArrivals.isEmpty) continue;

      currentArrivals.sort((a, b) => TimeUtils.remaining(a.intimeStr, now, intimeDura: a.intimeDura)!
          .compareTo(TimeUtils.remaining(b.intimeStr, now, intimeDura: b.intimeDura)!));
      nextArrivals.sort((a, b) => TimeUtils.remaining(a.intimeStr, now, intimeDura: a.intimeDura)!
          .compareTo(TimeUtils.remaining(b.intimeStr, now, intimeDura: b.intimeDura)!));

      final firstCurrent = currentArrivals.first;
      final firstNext = nextArrivals.first;

      final currentRemaining = TimeUtils.remaining(firstCurrent.intimeStr, now, intimeDura: firstCurrent.intimeDura)!;
      final nextRemaining = TimeUtils.remaining(firstNext.intimeStr, now, intimeDura: firstNext.intimeDura)!;

      final gap = nextRemaining.inMinutes - currentRemaining.inMinutes;
      if (gap > 0 && gap < 5) {
        warnings.add('${station.name}换乘仅剩 $gap 分钟，请加快步伐');
      }
    }

    return warnings;
  }
}
