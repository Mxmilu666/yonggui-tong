import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/arrival.dart';
import '../../core/models/station.dart';
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
    final favorites = ref.watch(favoritesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(station?.name ?? '列车到站'),
        actions: [
          if (stationId != null) IconButton(
            tooltip: favorites.contains(stationId) ? '取消收藏' : '收藏车站',
            icon: Icon(favorites.contains(stationId) ? Icons.star_rounded : Icons.star_outline_rounded),
            onPressed: () async {
              try {
                await ref.read(favoritesProvider.notifier).toggle(stationId!);
              } catch (_) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('收藏保存失败，请重试')));
              }
            },
          ),
          IconButton(tooltip: '选择车站', onPressed: () => _pick(context, ref), icon: const Icon(Icons.search)),
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
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [SliverToBoxAdapter(child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: stationId == null
                ? _StationPicker(onPick: () => _pick(context, ref))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (station != null) ...[
                      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        for (final line in station.lineIds) LineBadge(lineId: line),
                        if (station.lineIds.length > 1) const Text('换乘站'),
                      ]),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => context.push('/stations/${station.id}'),
                        icon: const Icon(Icons.info_outline, size: 18),
                        label: const Text('查看车站与线路'),
                      ),
                    ],
                    ArrivalBoard(stationId: stationId!),
                  ]),
            ),
          )))],
        ),
      ),
    );
  }
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
      EmptyState(
        title: '下一班，从哪一站出发？',
        message: '选择一个车站，查看各线路、各方向的到站时刻。',
        action: FilledButton.icon(onPressed: onPick, icon: const Icon(Icons.search), label: const Text('搜索车站')),
      ),
      if (catalog.hasError) ErrorState(message: '${catalog.error}', onRetry: () { ref.read(catalogProvider.notifier).refresh(); }),
      if (stations.isNotEmpty) ...[
        Text('我的收藏', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final station in stations) Card(
          child: ListTile(
            title: Text(station.name),
            subtitle: Text(station.lineIds.map((line) => '$line号线').join(' · ')),
            leading: const Icon(Icons.star_rounded),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/arrivals/${station.id}'),
          ),
        ),
      ] else Padding(
        padding: const EdgeInsets.all(16),
        child: Text('在到站页点亮星标，常用站就会出现在这里。', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ),
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
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now().toUtc();
    final snapshot = state.snapshot;
    final groups = <int, List<ArrivalDirection>>{};
    for (final direction in snapshot?.directions ?? <ArrivalDirection>[]) {
      groups.putIfAbsent(direction.lineId, () => []).add(direction);
    }
    final lines = groups.keys.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!compact) ...[
        Text('到站看板', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('时刻为北京时间 · 数据按运行图提供', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
      ],
      if (state.error != null) ...[
        ErrorState(
          message: snapshot == null ? state.error! : '${state.error}\n以下保留上次获取的数据，请留意更新时间。',
          compact: true,
          onRetry: () { ref.read(arrivalsProvider(stationId).notifier).refresh(); },
        ),
        const SizedBox(height: 12),
      ],
      if (snapshot == null && state.error == null) const ArrivalSkeleton(),
      if (snapshot != null) ...[
        if (state.loading) const LinearProgressIndicator(semanticsLabel: '正在更新到站时刻'),
        if (snapshot.directions.isEmpty)
          const EmptyState(title: '该站暂无到站数据', message: '接口未返回方向信息，不能据此判断运营状态。'),
        for (final line in lines) ...[
          if (!compact) ...[LineBadge(lineId: line), const SizedBox(height: 12)],
          _DirectionGroup(directions: groups[line]!..sort((a, b) => a.flag.compareTo(b.flag)), now: now, compact: compact),
          const SizedBox(height: 16),
        ],
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Icon(Icons.update, size: 16),
          Text('更新于 ${TimeUtils.formatBeijing(snapshot.fetchedAt)}', style: Theme.of(context).textTheme.bodySmall),
          if (!compact) TextButton.icon(
            onPressed: state.loading ? null : () { ref.read(arrivalsProvider(stationId).notifier).refresh(); },
            icon: const Icon(Icons.refresh, size: 18), label: const Text('刷新'),
          ),
        ]),
      ],
      if (!compact) ...[
        const SizedBox(height: 12),
        Text('暂无有效班次不代表已停运。方向编号由接口提供，暂无可靠的终点方向对应信息。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ]);
  }
}

class _DirectionGroup extends StatelessWidget {
  const _DirectionGroup({required this.directions, required this.now, required this.compact});
  final List<ArrivalDirection> directions;
  final DateTime now;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth >= 560 && !compact ? 2 : 1;
    final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (final direction in directions) SizedBox(width: width, child: _DirectionCard(direction: direction, now: now, compact: compact)),
    ]);
  });
}

class _DirectionCard extends StatelessWidget {
  const _DirectionCard({required this.direction, required this.now, required this.compact});
  final ArrivalDirection direction;
  final DateTime now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final valid = direction.validRuns(now);
    // Sort by actual remaining time, including a valid midnight crossing.
    valid.sort((a, b) => TimeUtils.remaining(a.intimeStr, now, intimeDura: a.intimeDura)!.compareTo(TimeUtils.remaining(b.intimeStr, now, intimeDura: b.intimeDura)!));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (compact) LineBadge(lineId: direction.lineId, small: true),
          Text('方向 ${direction.flag}', style: Theme.of(context).textTheme.titleSmall),
          const Icon(Icons.arrow_forward_rounded, size: 16),
        ]),
      ),
      if (valid.isEmpty) Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
        child: const Text('暂无有效班次'),
      ),
      for (final run in compact ? valid.take(1) : valid) Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ArrivalTile(lineId: direction.lineId, run: run, now: now),
      ),
    ]);
  }
}

class ArrivalSkeleton extends StatelessWidget {
  const ArrivalSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在载入到站时刻',
    child: ExcludeSemantics(child: Column(children: [
      for (var index = 0; index < 2; index++) Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 80, height: 16, color: Theme.of(context).colorScheme.surfaceContainerHighest),
          const SizedBox(height: 20),
          Container(width: 140, height: 32, color: Theme.of(context).colorScheme.surfaceContainerHighest),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ]),
      ),
    ])),
  );
}
