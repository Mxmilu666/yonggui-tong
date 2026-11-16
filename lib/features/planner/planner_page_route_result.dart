import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/favorite_route.dart';
import '../../core/models/route_plan.dart';
import '../../core/models/station.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';

class RouteResult extends ConsumerWidget {
  const RouteResult({super.key, required this.plan, required this.catalog});
  final RoutePlan plan;
  final StationCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plan.stops == 0) {
      return const EmptyState(title: '起终点为同一站', message: '无需乘车 · 估算 0 分钟', icon: Icons.check_circle_outline);
    }
    final scheme = Theme.of(context).colorScheme;
    final favoriteRoute = FavoriteRoute(
      originId: plan.originId,
      destinationId: plan.destinationId,
      name: '${catalog.stationById(plan.originId)!.name} → ${catalog.stationById(plan.destinationId)!.name}',
    );
    final isFavorited = ref.watch(favoriteRoutesProvider).contains(favoriteRoute);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('预计行程 · 仅供参考')),
            IconButton(
              icon: Icon(isFavorited ? Icons.favorite : Icons.favorite_border),
              tooltip: isFavorited ? '取消收藏路线' : '收藏路线',
              onPressed: () => ref.read(favoriteRoutesProvider.notifier).toggle(favoriteRoute),
            ),
          ]),
          const SizedBox(height: 8),
          Semantics(label: '估算 ${plan.minutes} 分钟，乘坐 ${plan.stops} 站，换乘 ${plan.transfers} 次',
            child: Text('${plan.minutes} 分钟', style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()], fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          Text('${plan.stops} 站 · ${plan.transfers == 0 ? '无需换乘' : '${plan.transfers} 次换乘'}'),
          const SizedBox(height: 12),
          const Text('估算，不含候车/延误；不代表实际运营方案。'),
        ]),
      ),
      const SizedBox(height: 24),
      for (var index = 0; index < plan.segments.length; index++) ...[
        if (index > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(children: [const Icon(Icons.transfer_within_a_station), const SizedBox(width: 8),
            Expanded(child: Text('在 ${catalog.stationById(plan.segments[index].stationIds.first)!.name} 换乘 · 估算 4 分钟'))])),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              LineBadge(lineId: plan.segments[index].lineId),
              Text('${plan.segments[index].stops} 站 · 估算 ${plan.segments[index].stops * 2} 分钟'),
            ]),
            const SizedBox(height: 12),
            for (final id in plan.segments[index].stationIds)
              ListTile(contentPadding: EdgeInsets.zero, minTileHeight: 48,
                leading: const Icon(Icons.radio_button_checked, size: 16),
                title: Text(catalog.stationById(id)!.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/stations/$id')),
          ],
        ))),
      ],
    ]);
  }
}
