import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/favorite_route.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';
import '../planner/journey_timing_panel.dart';
import '../planner/planner_page.dart' show routePlannerProvider;

class FavoriteRouteCard extends ConsumerWidget {
  const FavoriteRouteCard({super.key, required this.route});
  final FavoriteRoute route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final planner = ref.watch(routePlannerProvider).valueOrNull;
    final origin = catalog?.stationById(route.originId);
    final destination = catalog?.stationById(route.destinationId);
    final plan = origin == null || destination == null ? null : planner?.estimate(origin.id, destination.id);
    if (catalog == null || plan == null) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
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
            if (plan.stops > 0) ...[
              const SizedBox(height: 12),
              JourneyTimingPanel(plan: plan, catalog: catalog),
            ],
          ]),
        ),
      ),
    );
  }
}
