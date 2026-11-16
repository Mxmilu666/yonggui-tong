import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/line_colors.dart';
import '../../core/models/arrival.dart';
import '../../core/models/station.dart';
import '../../core/utils/direction_resolver.dart';
import '../../core/utils/time_utils.dart';
import '../../core/widgets/arrival_tile.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';

/// Station summary with the next train of every direction; tapping opens its arrival board.
class StationArrivalCard extends ConsumerWidget {
  const StationArrivalCard({super.key, required this.station});
  final Station station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(arrivalsProvider(station.id));
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now().toUtc();
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final snapshot = state.snapshot;
    final directions = [...?snapshot?.directions]
      ..sort((a, b) => a.lineId != b.lineId ? a.lineId.compareTo(b.lineId) : a.flag.compareTo(b.flag));
    final anyRun = directions.any((direction) => direction.upcoming(now).isNotEmpty);
    return Card.outlined(
      child: InkWell(
        onTap: () => context.go('/arrivals/${station.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Hero(tag: 'station-${station.id}', child: Material(
                type: MaterialType.transparency,
                child: Text(station.name, style: text.titleMedium, overflow: TextOverflow.ellipsis)))),
              const SizedBox(width: 8),
              for (final line in station.lineIds) Padding(
                padding: const EdgeInsets.only(left: 4),
                child: LineBadge(lineId: line, small: true),
              ),
            ]),
            const SizedBox(height: 8),
            if (snapshot == null && state.loading) const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(semanticsLabel: '正在查询到站'),
            ),
            if (snapshot != null && !anyRun) Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(Icons.bedtime_outlined, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('当前时段暂无班次', style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
              ]),
            ),
            if (anyRun) for (final direction in directions)
              _NextTrainRow(direction: direction, now: now, catalog: catalog),
            if (state.error != null) Row(children: [
              Expanded(child: Text(snapshot == null ? '暂时无法获取到站'
                : '更新失败 · 显示 ${now.difference(snapshot.fetchedAt).inMinutes.clamp(0, 9999)} 分钟前数据',
                style: text.bodySmall?.copyWith(color: colors.error))),
              IconButton(tooltip: '重试', onPressed: () => ref.read(arrivalsProvider(station.id).notifier).refresh(),
                icon: const Icon(Icons.refresh)),
            ]) else if (snapshot != null) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('更新于 ${TimeUtils.formatBeijing(snapshot.fetchedAt)}',
                style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NextTrainRow extends StatelessWidget {
  const _NextTrainRow({required this.direction, required this.now, required this.catalog});
  final ArrivalDirection direction;
  final DateTime now;
  final StationCatalog? catalog;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final runs = direction.upcoming(now);
    final next = runs.isEmpty ? null : runs.first;
    final remaining = next?.arriveAt.difference(now);
    final dwelling = next?.isDwelling(now) ?? false;
    return SizedBox(
      height: 40,
      child: Row(children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(
          color: LineColors.colorOf(direction.lineId), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(child: Text(DirectionResolver.label(lineId: direction.lineId, flag: direction.flag, catalog: catalog),
          style: text.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (next == null || remaining == null)
          Text('暂无班次', style: text.bodyMedium?.copyWith(color: muted))
        else ...[
          Text(dwelling ? '${next.run.outTimeStr.substring(0, 5)} 发车' : next.run.intimeStr.substring(0, 5),
            style: text.bodySmall?.copyWith(color: muted, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 10),
          CountdownText(remaining: remaining, large: false),
        ],
      ]),
    );
  }
}
