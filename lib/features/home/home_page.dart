import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/station.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';
import '../arrivals/station_arrival_card.dart';
import '../search/station_search.dart';
import 'favorite_route_card.dart';

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
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
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
            const SliverAppBar.large(title: Text('甬轨通')),
            SliverToBoxAdapter(child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('宁波地铁出行助手', style: text.bodyMedium?.copyWith(color: muted)),
                  const SizedBox(height: 16),
                  StationSearchBar(onTap: () async {
                    final station = await showStationSearch(context, ref);
                    if (station != null && context.mounted) context.go('/arrivals/${station.id}');
                  }),
                  const SizedBox(height: 16),
                  const _QuickActions(),
                  _SectionHeader(
                    title: favoriteStations.isNotEmpty ? '常用站点' : '热门站点',
                    subtitle: favoriteStations.isNotEmpty ? null : '在到站页点亮星标，这里会换成你的常用站',
                  ),
                  if (catalog.hasError) ...[
                    ErrorState(message: '${catalog.error}', onRetry: () { ref.read(catalogProvider.notifier).refresh(); }),
                    const SizedBox(height: 12),
                  ],
                  if (data == null && catalog.isLoading) const LinearProgressIndicator(semanticsLabel: '正在载入车站目录'),
                  if (data != null) _ResponsiveColumn(children: [
                    for (final station in common) StationArrivalCard(station: station),
                  ]),
                  if (favoriteRoutes.isNotEmpty) ...[
                    const _SectionHeader(title: '收藏路线', subtitle: '现在从起点出发，换乘赶不赶得上'),
                    _ResponsiveColumn(children: [
                      for (final route in favoriteRoutes) FavoriteRouteCard(route: route),
                    ]),
                  ],
                  const _SectionHeader(title: '线路'),
                  if (data != null) _LineGrid(lines: data.lineIds),
                  const SizedBox(height: 32),
                  Text('非官方出行工具 · 数据来自宁波地铁 App 后端\n到站时刻仅供参考，请以现场信息为准。',
                    textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: muted)),
                ]),
              ),
            ))),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(title, style: text.titleMedium)),
        if (subtitle != null) Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(subtitle!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ]),
    );
  }
}

/// One column on phones, two columns from 560dp.
class _ResponsiveColumn extends StatelessWidget {
  const _ResponsiveColumn({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth >= 560 ? 2 : 1;
    final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (final child in children) SizedBox(width: width, child: child),
    ]);
  });
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) => Row(children: [
    _QuickAction(icon: Icons.alt_route, label: '行程估算', onTap: () => context.push('/planner')),
    const SizedBox(width: 8),
    _QuickAction(icon: Icons.format_list_bulleted, label: '线路列表', onTap: () => context.push('/lines')),
    const SizedBox(width: 8),
    _QuickAction(icon: Icons.hub_outlined, label: '线网图', onTap: () => context.go('/map')),
  ]);
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(child: Card.filled(
      color: colors.secondaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(children: [
            Icon(icon, color: colors.onSecondaryContainer),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.onSecondaryContainer)),
          ]),
        ),
      ),
    ));
  }
}

class _LineGrid extends StatelessWidget {
  const _LineGrid({required this.lines});
  final List<int> lines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth >= 560 ? 5 : 3;
    final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final line in lines) SizedBox(width: width, child: Card.outlined(
        child: InkWell(
          onTap: () => context.push('/lines/$line'),
          child: Semantics(
            button: true,
            label: '$line号线',
            child: ExcludeSemantics(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Hero(tag: 'line-$line', child: LineAvatar(lineId: line)),
                const SizedBox(height: 6),
                Text('$line号线', style: Theme.of(context).textTheme.labelLarge),
              ]),
            )),
          ),
        ),
      )),
    ]);
  });
}
