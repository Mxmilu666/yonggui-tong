import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/line_colors.dart';
import '../../core/models/station.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';

class LinesPage extends ConsumerWidget {
  const LinesPage({super.key, this.lineId});
  final int? lineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: Text(lineId == null ? '宁波地铁线路' : '$lineId号线')),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Padding(padding: const EdgeInsets.all(16),
          child: ErrorState(message: '$error', onRetry: () => ref.read(catalogProvider.notifier).refresh()))),
        data: (data) => Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: lineId == null ? _LineList(catalog: data) : _LineDetail(lineId: lineId!, catalog: data),
        )),
      ),
    );
  }
}

class _LineList extends StatelessWidget {
  const _LineList({required this.catalog});
  final StationCatalog catalog;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 8),
    itemCount: LineColors.ids.length,
    itemBuilder: (context, index) {
      final id = LineColors.ids[index];
      final stations = catalog.stationsForLine(id);
      return ListTile(
        minTileHeight: 72,
        leading: Hero(tag: 'line-$id', child: LineAvatar(lineId: id, size: 40)),
        title: Text('$id号线'),
        subtitle: Text(stations.isEmpty ? '暂无目录数据'
          : '${stations.first.name} ↔ ${stations.last.name} · ${stations.length} 站'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/lines/$id'),
      );
    },
  );
}

class _LineDetail extends StatelessWidget {
  const _LineDetail({required this.lineId, required this.catalog});
  final int lineId;
  final StationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final stations = catalog.stationsForLine(lineId);
    final color = LineColors.colorOf(lineId);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Card.filled(child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(width: 4, color: color))),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Hero(tag: 'line-$lineId', child: LineAvatar(lineId: lineId, size: 48)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stations.isEmpty ? '暂无站点目录' : '${stations.first.name} ↔ ${stations.last.name}',
                  style: text.titleLarge),
                const SizedBox(height: 4),
                Text('${stations.length} 站 · ${stations.where((s) => s.lineIds.length > 1).length} 个换乘站 · 按官方站序',
                  style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
              ])),
            ]),
          ),
        )),
      )),
      SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        sliver: SliverList.builder(
          itemCount: stations.length,
          itemBuilder: (context, index) {
            final station = stations[index];
            final transfer = station.lineIds.length > 1;
            Widget rail(bool visible) => Expanded(child: Container(width: 4, color: visible ? color : Colors.transparent));
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.push('/stations/${station.id}'),
              child: SizedBox(height: 64, child: Row(children: [
                SizedBox(width: 32, child: Stack(alignment: Alignment.center, children: [
                  Column(children: [rail(index > 0), rail(index < stations.length - 1)]),
                  Container(width: transfer ? 16 : 12, height: transfer ? 16 : 12,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surface,
                      border: Border.all(color: transfer ? colors.onSurface : color, width: transfer ? 3 : 2.5))),
                ])),
                const SizedBox(width: 12),
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(station.name, style: text.bodyLarge),
                    if (transfer) Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(spacing: 4, runSpacing: 4, children: [
                        for (final other in station.lineIds.where((id) => id != lineId))
                          LineBadge(lineId: other, small: true),
                      ]),
                    ),
                  ])),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ])),
            );
          },
        ),
      ),
    ]);
  }
}
