import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/line_colors.dart';
import '../../core/models/arrival.dart';
import '../../core/models/station.dart';
import '../../core/utils/direction_resolver.dart';
import '../../core/utils/time_utils.dart';
import '../../core/widgets/arrival_tile.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';
import '../search/station_search.dart';

class ArrivalsPage extends ConsumerWidget {
  const ArrivalsPage({super.key, this.stationId});

  final int? stationId;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final station = await showStationSearch(context, ref);
    if (station != null && context.mounted) context.go('/arrivals/${station.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final station = stationId == null ? null : catalog.valueOrNull?.stationById(stationId!);
    final favorite = stationId != null && ref.watch(favoritesProvider).contains(stationId);
    return Scaffold(
      appBar: AppBar(
        title: Text(station?.name ?? '到站'),
        actions: [
          if (stationId != null) IconButton(
            tooltip: favorite ? '取消收藏' : '收藏车站',
            isSelected: favorite,
            icon: const Icon(Icons.star_outline_rounded),
            selectedIcon: const Icon(Icons.star_rounded),
            onPressed: () async {
              try {
                await ref.read(favoritesProvider.notifier).toggle(stationId!);
              } catch (_) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('收藏保存失败，请重试')));
              }
            },
          ),
          if (stationId != null) IconButton(tooltip: '选择车站', onPressed: () => _pick(context, ref), icon: const Icon(Icons.search)),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (stationId != null) {
            await ref.read(arrivalsProvider(stationId!).notifier).refresh();
          } else {
            await ref.read(catalogProvider.notifier).refresh();
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: stationId == null
              ? _StationPicker(onPick: () => _pick(context, ref))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (station != null) ...[
                    _StationHeader(station: station),
                    const SizedBox(height: 16),
                  ],
                  ArrivalBoard(stationId: stationId!),
                ]),
          ))],
        ),
      ),
    );
  }
}

class _StationHeader extends StatelessWidget {
  const _StationHeader({required this.station});
  final Station station;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final line in station.lineIds) LineBadge(lineId: line),
      if (station.lineIds.length > 1) Text('换乘站', style: Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ])),
    TextButton(onPressed: () => context.push('/stations/${station.id}'), child: const Text('车站详情')),
  ]);
}

class _StationPicker extends ConsumerWidget {
  const _StationPicker({required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final favorites = ref.watch(favoritesProvider);
    final stations = catalog.valueOrNull?.stations.where((station) => favorites.contains(station.id)).toList() ?? <Station>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StationSearchBar(onTap: onPick),
      const SizedBox(height: 24),
      if (catalog.hasError) ...[
        ErrorState(message: '${catalog.error}', onRetry: () { ref.read(catalogProvider.notifier).refresh(); }),
        const SizedBox(height: 16),
      ],
      if (stations.isEmpty)
        const EmptyState(
          icon: Icons.star_outline_rounded,
          title: '还没有收藏车站',
          message: '搜索车站后点亮星标，常用站会出现在这里。',
        )
      else ...[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('收藏车站', style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ),
        Card.outlined(child: Column(children: [
          for (final (index, station) in stations.indexed) ...[
            if (index > 0) const Divider(indent: 16, endIndent: 16),
            ListTile(
              title: Text(station.name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final line in station.lineIds) LineBadge(lineId: line, small: true),
                ]),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/arrivals/${station.id}'),
            ),
          ],
        ])),
      ],
    ]);
  }
}

class ArrivalBoard extends ConsumerWidget {
  const ArrivalBoard({super.key, required this.stationId, this.compact = false});

  final int stationId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(arrivalsProvider(stationId));
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now().toUtc();
    final snapshot = state.snapshot;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final groups = <int, List<ArrivalDirection>>{};
    for (final direction in snapshot?.directions ?? <ArrivalDirection>[]) {
      groups.putIfAbsent(direction.lineId, () => []).add(direction);
    }
    final lines = groups.keys.toList()..sort();
    void refresh() => ref.read(arrivalsProvider(stationId).notifier).refresh();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!compact && snapshot != null) SizedBox(
        height: 48,
        child: Row(children: [
          Icon(Icons.update, size: 16, color: muted),
          const SizedBox(width: 6),
          Expanded(child: Text('更新于 ${TimeUtils.formatBeijing(snapshot.fetchedAt)} · 北京时间',
            style: text.bodySmall?.copyWith(color: muted, fontFeatures: const [FontFeature.tabularFigures()]))),
          if (state.loading)
            const Padding(padding: EdgeInsets.all(14), child: SizedBox.square(dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: '正在更新到站时刻')))
          else
            IconButton(tooltip: '刷新到站', onPressed: refresh, icon: const Icon(Icons.refresh)),
        ]),
      ),
      if (state.error != null) ...[
        ErrorState(
          message: snapshot == null ? state.error!
            : '当前显示 ${now.difference(snapshot.fetchedAt).inMinutes.clamp(0, 9999)} 分钟前的数据。',
          compact: true,
          onRetry: refresh,
        ),
        const SizedBox(height: 12),
      ],
      if (snapshot == null && state.error == null) const ArrivalSkeleton(),
      if (snapshot != null) ...[
        if (snapshot.directions.isEmpty)
          const EmptyState(title: '当前时段暂无班次（可能已停运）', message: '接口未返回方向信息，请以车站现场信息为准。', icon: Icons.bedtime_outlined),
        for (final (index, line) in lines.indexed) ...[
          if (index > 0) SizedBox(height: compact ? 8 : 12),
          _LineArrivalCard(lineId: line,
            directions: groups[line]!..sort((a, b) => a.flag.compareTo(b.flag)),
            now: now, compact: compact, catalog: catalog),
        ],
      ],
      if (!compact) ...[
        const SizedBox(height: 16),
        Text('时刻按运行图提供，仅供参考；暂无有效班次不代表已停运。方向按已核对的线路终点展示，短线列车以站台显示为准。',
          style: text.bodySmall?.copyWith(color: muted)),
      ],
    ]);
  }
}

class _LineArrivalCard extends StatelessWidget {
  const _LineArrivalCard({required this.lineId, required this.directions, required this.now,
    required this.compact, required this.catalog});
  final int lineId;
  final List<ArrivalDirection> directions;
  final DateTime now;
  final bool compact;
  final StationCatalog? catalog;

  @override
  Widget build(BuildContext context) => Card.outlined(
    child: DecoratedBox(
      decoration: BoxDecoration(border: Border(left: BorderSide(width: 4, color: LineColors.colorOf(lineId)))),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 12 : 16, 16, compact ? 12 : 8),
        child: LayoutBuilder(builder: (context, constraints) {
          final sections = [
            for (final direction in directions) _DirectionSection(
              direction: direction, now: now, compact: compact, catalog: catalog),
          ];
          final sideBySide = !compact && constraints.maxWidth >= 520 && sections.length > 1;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerLeft, child: LineBadge(lineId: lineId, small: compact)),
            SizedBox(height: compact ? 8 : 12),
            if (sideBySide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (index, section) in sections.indexed) ...[
                  if (index > 0) const SizedBox(width: 24),
                  Expanded(child: section),
                ],
              ])
            else
              for (final (index, section) in sections.indexed) ...[
                if (index > 0) Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
                  child: const Divider(),
                ),
                section,
              ],
          ]);
        }),
      ),
    ),
  );
}

class _DirectionSection extends StatelessWidget {
  const _DirectionSection({required this.direction, required this.now,
    required this.compact, required this.catalog});
  final ArrivalDirection direction;
  final DateTime now;
  final bool compact;
  final StationCatalog? catalog;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final runs = direction.upcoming(now);
    final next = runs.isEmpty ? null : runs.first;
    final remaining = next == null ? null
      : TimeUtils.remaining(next.intimeStr, now, intimeDura: next.intimeDura);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Text(
          DirectionResolver.label(lineId: direction.lineId, flag: direction.flag, catalog: catalog),
          style: compact ? text.titleSmall : text.titleMedium)),
        if (remaining != null) CountdownText(remaining: remaining, large: !compact),
      ]),
      const SizedBox(height: 2),
      if (next == null)
        Text('暂无有效班次', style: text.bodyMedium?.copyWith(color: muted))
      else
        Text('${next.intimeStr} 到站 · 第${next.sequence}班',
          style: text.bodySmall?.copyWith(color: muted, fontFeatures: const [FontFeature.tabularFigures()])),
      if (!compact && runs.length > 1) ...[
        const SizedBox(height: 4),
        for (final run in runs.skip(1).take(3))
          ArrivalTile(lineId: direction.lineId, run: run, now: now),
      ],
    ]);
  }
}

class ArrivalSkeleton extends StatelessWidget {
  const ArrivalSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width, double height) => Container(width: width, height: height,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(4)));
    return Semantics(
      label: '正在载入到站时刻',
      child: ExcludeSemantics(child: Column(children: [
        for (var index = 0; index < 2; index++) Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card.outlined(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              bar(56, 20),
              const SizedBox(height: 16),
              Row(children: [bar(96, 20), const Spacer(), bar(64, 28)]),
              const SizedBox(height: 8),
              bar(140, 14),
            ]),
          )),
        ),
      ])),
    );
  }
}
