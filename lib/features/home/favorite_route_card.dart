import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/favorite_route.dart';
import '../../core/models/route_plan.dart';
import '../../core/models/station.dart';
import '../../core/utils/transfer_timing.dart';
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
    final origin = catalog?.stationById(route.originId);
    final destination = catalog?.stationById(route.destinationId);
    final plan = origin == null || destination == null ? null : planner?.estimate(origin.id, destination.id);
    if (catalog == null || plan == null) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final connections = <TransferConnection>[
      for (var index = 0; index < plan.segments.length - 1; index++)
        ?_connection(ref, plan, index, catalog, now),
    ];
    return Card.outlined(
      child: InkWell(
        onTap: () => context.push('/planner?from=${route.originId}&to=${route.destinationId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text('${origin!.name} → ${destination!.name}', style: text.titleMedium)),
              const SizedBox(width: 12),
              Text('约 ${plan.minutes} 分钟', style: text.titleSmall?.copyWith(color: colors.primary,
                fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 4, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final (index, segment) in plan.segments.indexed) ...[
                if (index > 0) Icon(Icons.chevron_right, size: 16, color: colors.onSurfaceVariant),
                LineBadge(lineId: segment.lineId, small: true),
              ],
              const SizedBox(width: 4),
              Text('${plan.stops} 站 · ${plan.transfers == 0 ? '无需换乘' : '换乘 ${plan.transfers} 次'}',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ]),
            for (final connection in connections) ...[
              const SizedBox(height: 12),
              _TransferNote(connection: connection, station: catalog.stationById(connection.stationId)!),
            ],
          ]),
        ),
      ),
    );
  }

  TransferConnection? _connection(WidgetRef ref, RoutePlan plan, int index, StationCatalog catalog, DateTime now) {
    final snapshot = ref.watch(arrivalsProvider(plan.segments[index].stationIds.last)).snapshot;
    return snapshot == null ? null
      : transferConnection(plan: plan, index: index, snapshot: snapshot, catalog: catalog, now: now);
  }
}

class _TransferNote extends StatelessWidget {
  const _TransferNote({required this.connection, required this.station});
  final TransferConnection connection;
  final Station station;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final tight = connection.tight;
    final minutes = connection.gap.inMinutes;
    final gap = minutes < 1 ? '不足 1 分钟' : '$minutes 分钟';
    final foreground = tight ? colors.onTertiaryContainer : colors.onSurfaceVariant;
    final schedule = '${connection.fromLine}号线 ${connection.arrive.intimeStr} 到，'
      '${connection.toLine}号线 ${connection.depart.outTimeStr} 开';
    return Semantics(
      label: '${station.name}换乘${tight ? '紧张' : ''}，间隔$gap，$schedule，按时刻表推算',
      child: ExcludeSemantics(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tight ? colors.tertiaryContainer : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(tight ? Icons.directions_run : Icons.transfer_within_a_station, size: 20, color: foreground),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tight ? '${station.name}换乘仅 $gap' : '${station.name}换乘约 $gap',
              style: text.labelLarge?.copyWith(color: foreground)),
            const SizedBox(height: 2),
            Text('$schedule · 按时刻表推算',
              style: text.bodySmall?.copyWith(color: foreground, fontFeatures: const [FontFeature.tabularFigures()])),
          ])),
        ]),
      )),
    );
  }
}
