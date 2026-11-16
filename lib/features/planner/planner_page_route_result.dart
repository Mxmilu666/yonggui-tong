import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/line_colors.dart';
import '../../core/models/favorite_route.dart';
import '../../core/models/route_plan.dart';
import '../../core/models/station.dart';
import '../../core/utils/direction_resolver.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';
import 'journey_timing_panel.dart';

class RouteResult extends ConsumerWidget {
  const RouteResult({super.key, required this.plan, required this.catalog});
  final RoutePlan plan;
  final StationCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plan.stops == 0) {
      return const EmptyState(title: '起终点为同一站', message: '无需乘车 · 估算 0 分钟', icon: Icons.check_circle_outline);
    }
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final favoriteRoute = FavoriteRoute(
      originId: plan.originId,
      destinationId: plan.destinationId,
      name: '${catalog.stationById(plan.originId)!.name} → ${catalog.stationById(plan.destinationId)!.name}',
    );
    final isFavorited = ref.watch(favoriteRoutesProvider).contains(favoriteRoute);
    Future<void> toggleFavorite() async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref.read(favoriteRoutesProvider.notifier).toggle(favoriteRoute);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(isFavorited ? '已取消收藏路线' : '已收藏，可在首页查看')));
      } catch (_) {
        messenger.showSnackBar(const SnackBar(content: Text('收藏保存失败，请重试')));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card.filled(
        color: colors.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('预计行程 · 仅供参考', style: text.labelLarge?.copyWith(color: colors.onSecondaryContainer)),
              const SizedBox(height: 8),
              Semantics(label: '估算 ${plan.minutes} 分钟，乘坐 ${plan.stops} 站，换乘 ${plan.transfers} 次',
                child: ExcludeSemantics(child: Text('${plan.minutes} 分钟', style: text.displaySmall?.copyWith(
                  color: colors.onSecondaryContainer, fontFeatures: const [FontFeature.tabularFigures()])))),
              const SizedBox(height: 4),
              Text('${plan.stops} 站 · ${plan.transfers == 0 ? '无需换乘' : '${plan.transfers} 次换乘'}',
                style: text.bodyLarge?.copyWith(color: colors.onSecondaryContainer)),
            ])),
            IconButton(
              tooltip: isFavorited ? '取消收藏路线' : '收藏路线',
              isSelected: isFavorited,
              color: colors.onSecondaryContainer,
              icon: const Icon(Icons.favorite_border),
              selectedIcon: const Icon(Icons.favorite),
              onPressed: toggleFavorite,
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text('估算，不含候车/延误；不代表实际运营方案。',
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      ),
      const SizedBox(height: 16),
      Card.outlined(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('现在出发', style: text.titleSmall),
          const SizedBox(height: 12),
          JourneyTimingPanel(plan: plan, catalog: catalog),
        ]),
      )),
      const SizedBox(height: 16),
      for (var index = 0; index < plan.segments.length; index++) ...[
        if (index > 0) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            Icon(Icons.transfer_within_a_station, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text('在 ${catalog.stationById(plan.segments[index].stationIds.first)!.name} 换乘 · 估算 4 分钟',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant))),
          ]),
        ),
        _SegmentCard(segment: plan.segments[index], catalog: catalog),
      ],
    ]);
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({required this.segment, required this.catalog});
  final RouteSegment segment;
  final StationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final flag = DirectionResolver.flagToward(lineId: segment.lineId,
      fromId: segment.stationIds.first, toId: segment.stationIds.last, catalog: catalog);
    final direction = flag == null ? null
      : DirectionResolver.label(lineId: segment.lineId, flag: flag, catalog: catalog);
    final ids = segment.stationIds;
    return Card.outlined(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            LineBadge(lineId: segment.lineId),
            if (direction != null && direction.startsWith('往 ')) Text(direction, style: text.titleSmall),
            Text('${segment.stops} 站 · 估算 ${segment.stops * 2} 分钟',
              style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        for (final (index, id) in ids.indexed) _TimelineStop(
          lineId: segment.lineId,
          name: catalog.stationById(id)!.name,
          first: index == 0,
          last: index == ids.length - 1,
          onTap: () => context.push('/stations/$id'),
        ),
      ]),
    ));
  }
}

class _TimelineStop extends StatelessWidget {
  const _TimelineStop({required this.lineId, required this.name, required this.first,
    required this.last, required this.onTap});
  final int lineId;
  final String name;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = LineColors.colorOf(lineId);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final major = first || last;
    Widget rail(bool visible) => Expanded(child: Container(width: 4, color: visible ? color : Colors.transparent));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: major ? 48 : 40,
        child: Row(children: [
          SizedBox(width: 24, child: Stack(alignment: Alignment.center, children: [
            Column(children: [rail(!first), rail(!last)]),
            Container(
              width: major ? 14 : 8, height: major ? 14 : 8,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: major ? colors.surface : color,
                border: major ? Border.all(color: color, width: 3) : null),
            ),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: major ? text.titleSmall : text.bodyMedium)),
          Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
        ]),
      ),
    );
  }
}
