import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/line_colors.dart';
import '../../core/models/arrival.dart';
import '../../core/models/station.dart';
import '../../core/utils/direction_resolver.dart';
import '../../core/utils/time_utils.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/line_badge.dart';
import 'favorite_route_card.dart';
import '../../data/providers.dart';
import '../search/station_search.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final data = catalog.valueOrNull;
    final favorites = ref.watch(favoritesProvider);
    final favoriteRoutes = ref.watch(favoriteRoutesProvider);
    final favoriteStations = data?.stations.where((station) => favorites.contains(station.id)).toList() ?? <Station>[];
    final common = favoriteStations.isNotEmpty
      ? favoriteStations
      : <Station>[
          for (final name in ['鼓楼', '宁波火车站', '东门口（天一广场）'])
            ...?data?.stations.where((station) => station.name == name).take(1),
        ];
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(catalogProvider.notifier).refresh();
          for (final station in common) {
            await ref.read(arrivalsProvider(station.id).notifier).refresh();
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('甬轨通'),
              actions: [
                IconButton(tooltip: '我的与设置', onPressed: () => context.go('/settings'), icon: const Icon(Icons.tune_rounded)),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('宁波地铁出行助手', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(28)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('沿着轨道\n遇见甬城', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: colors.onPrimaryContainer, fontWeight: FontWeight.w700, height: 1.3)),
                          const SizedBox(height: 12),
                          Text('查一站到站，从容出发。', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onPrimaryContainer)),
                        ])),
                        const SizedBox(width: 12),
                        SizedBox(width: 64, height: 84, child: CustomPaint(painter: _RailMark(colors.onPrimaryContainer))),
                      ]),
                      const SizedBox(height: 24),
                      SearchBar(
                        hintText: '搜索车站',
                        leading: const Icon(Icons.search_rounded),
                        trailing: const [Icon(Icons.arrow_forward_rounded)],
                        onTap: () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          final station = await showStationSearch(context, ref);
                          if (station != null && context.mounted) context.go('/arrivals/${station.id}');
                        },
                      ),
                    ]),
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(child: Text(favoriteStations.isNotEmpty ? '常用站点' : '热门站点', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))),
                    TextButton(onPressed: () => context.go('/arrivals'), child: const Text('全部车站')),
                  ]),
                  Text(favoriteStations.isNotEmpty ? '你的收藏，一眼看到下一班' : '收藏常用站，让出行更顺手', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  if (catalog.hasError) ...[
                    ErrorState(message: '${catalog.error}', onRetry: () { ref.read(catalogProvider.notifier).refresh(); }),
                    const SizedBox(height: 16),
                  ],
                  if (data == null && catalog.isLoading) const _HomeSkeleton(),
                  if (data != null) ...[
                    if (common.isEmpty) OutlinedButton.icon(
                      onPressed: () => context.go('/arrivals'),
                      icon: const Icon(Icons.search), label: const Text('选择车站查看到站'),
                    ),
                    LayoutBuilder(builder: (context, constraints) =>
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final station in common) Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: SizedBox(width: constraints.maxWidth >= 560
                              ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth * .92,
                              child: _CommonStationCard(station: station)),
                          ),
                        ]),
                      )),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.info_outline_rounded, size: 20, color: colors.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text('到站信息仅对应卡片中的车站，不代表全网运营状态；暂无班次不等于停运。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/planner'),
                    icon: const Icon(Icons.alt_route), label: const Text('选起终点，估算行程'),
                  ),
                  if (favoriteRoutes.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Row(children: [
                      Expanded(child: Text('收藏路线', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))),
                      TextButton(onPressed: () => context.push('/planner'), child: const Text('估算行程')),
                    ]),
                    Text('快速查看收藏路线的换乘提醒', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 16),
                    LayoutBuilder(builder: (context, constraints) =>
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final route in favoriteRoutes) Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: SizedBox(width: constraints.maxWidth >= 560
                              ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth * .92,
                              child: FavoriteRouteCard(route: route)),
                          ),
                        ]),
                      )),
                  ],
                  Row(children: [
                    Expanded(child: Text('探索线路', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))),
                    TextButton(onPressed: () => context.go('/map'), child: const Text('查看线网')),
                  ]),
                  const SizedBox(height: 12),
                  if (data != null) LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 560 ? 5 : 3;
                    final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final line in data.lineIds) SizedBox(width: width, child: _LineShortcut(line: line)),
                    ]);
                  }),
                  const SizedBox(height: 24),
                  Text('非官方出行工具 · 数据来自宁波地铁 App 后端\n到站时刻仅供参考，请以现场信息为准。', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                ]),
              ),
            ))),
          ],
        ),
      ),
    );
  }
}

class _CommonStationCard extends ConsumerWidget {
  const _CommonStationCard({required this.station});
  final Station station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(arrivalsProvider(station.id));
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now().toUtc();
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final valid = <(ArrivalDirection, ArrivalRun)>[
      for (final direction in state.snapshot?.directions ?? <ArrivalDirection>[])
        for (final run in direction.validRuns(now)) (direction, run),
    ];
    valid.sort((a, b) => TimeUtils.remaining(a.$2.intimeStr, now, intimeDura: a.$2.intimeDura)!.compareTo(TimeUtils.remaining(b.$2.intimeStr, now, intimeDura: b.$2.intimeDura)!));
    final next = valid.isEmpty ? null : valid.first;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/arrivals/${station.id}'),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(width: 5, color: LineColors.colorOf(station.lineIds.first)))),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Hero(tag: 'station-${station.id}',
              child: Material(color: Colors.transparent, child: Text(station.name,
                style: Theme.of(context).textTheme.titleLarge)))),
              const Icon(Icons.arrow_forward_rounded, size: 20)]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final line in station.lineIds) LineBadge(lineId: line, small: true)]),
            const SizedBox(height: 20),
            if (state.loading && state.snapshot == null) const LinearProgressIndicator(semanticsLabel: '正在查询到站'),
            if (state.snapshot != null) ...[
              Semantics(label: '${station.name}当前班次状态', child: Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(next == null ? Icons.bedtime_outlined : Icons.train_outlined, size: 16),
                label: Text(next == null ? '当前时段暂无班次' : '运营中'),
              )),
              Semantics(label: next == null ? '暂无班次' : '下一班 ${TimeUtils.countdown(TimeUtils.remaining(next.$2.intimeStr, now, intimeDura: next.$2.intimeDura)!)}',
                child: AnimatedSwitcher(duration: const Duration(milliseconds: 200),
                  child: Text(next == null ? '暂无有效班次' : TimeUtils.countdown(TimeUtils.remaining(next.$2.intimeStr, now, intimeDura: next.$2.intimeDura)!),
                    key: ValueKey(next?.$2.intimeStr),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: colors.primary, fontWeight: FontWeight.w600)))),
              const SizedBox(height: 8),
              Text(next == null ? '点击查看各线路、各方向' :
                '${next.$1.lineId}号线 · ${DirectionResolver.label(lineId: next.$1.lineId, flag: next.$1.flag, catalog: catalog)} · ${next.$2.intimeStr}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 12),
              Text('更新于 ${TimeUtils.formatBeijing(state.snapshot!.fetchedAt)}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(state.snapshot == null ? '暂时无法获取到站，点击重试' : '更新失败 · 当前为上次数据', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.error)),
              if (state.snapshot != null) Text('数据更新于 ${now.difference(state.snapshot!.fetchedAt).inMinutes.clamp(0, 9999)} 分钟前',
                style: Theme.of(context).textTheme.bodySmall),
              TextButton.icon(onPressed: () => ref.read(arrivalsProvider(station.id).notifier).refresh(),
                icon: const Icon(Icons.refresh), label: const Text('重试')),
            ],
          ]),
        ),
      ),
    );
  }
}

class _LineShortcut extends StatelessWidget {
  const _LineShortcut({required this.line});
  final int line;

  @override
  Widget build(BuildContext context) => Material(
    color: LineColors.colorOf(line).withValues(alpha: .12),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/lines/$line'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 18),
        child: Column(children: [
          Container(width: 12, height: 4, decoration: BoxDecoration(color: LineColors.colorOf(line), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 10),
          Text('$line号线', style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
        ]),
      ),
    ),
  );
}

class _RailMark extends CustomPainter {
  _RailMark(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 4..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(12, 6)..lineTo(12, 34)..quadraticBezierTo(12, 48, 26, 48)..lineTo(38, 48)..quadraticBezierTo(52, 48, 52, 62)..lineTo(52, 78);
    canvas.drawPath(path, paint);
    canvas.drawLine(const Offset(28, 6), const Offset(28, 30), paint);
    canvas.drawLine(const Offset(36, 62), const Offset(36, 78), paint);
    paint.style = PaintingStyle.fill;
    for (final point in [const Offset(12, 8), const Offset(12, 28), const Offset(32, 48), const Offset(52, 76)]) {
      canvas.drawCircle(point, 4, paint);
    }
  }

  @override
  bool shouldRepaint(_RailMark oldDelegate) => color != oldDelegate.color;
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('正在载入真实车站目录'), SizedBox(height: 16), LinearProgressIndicator()]),
  );
}
