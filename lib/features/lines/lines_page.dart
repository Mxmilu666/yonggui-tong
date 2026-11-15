import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/line_colors.dart';
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
        error: (error, _) => Center(child: FilledButton.tonal(
          onPressed: () => ref.read(catalogProvider.notifier).refresh(),
          child: const Text('目录加载失败，点击重试'),
        )),
        data: (data) {
          if (lineId == null) {
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: LineColors.ids.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final id = LineColors.ids[index];
                final stations = data.stationsForLine(id);
                return Card(child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(backgroundColor: LineColors.colorOf(id),
                    foregroundColor: LineColors.onColorOf(id), child: Text('$id')),
                  title: Text('$id号线'),
                  subtitle: Text(stations.isEmpty ? '暂无目录数据' : '${stations.first.name} — ${stations.last.name}\n${stations.length} 个站点'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/lines/$id'),
                ));
              },
            );
          }
          final stations = data.stationsForLine(lineId!);
          return Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: LineColors.colorOf(lineId!).withValues(alpha: .1),
                  border: Border(top: BorderSide(width: 5, color: LineColors.colorOf(lineId!))),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Hero(tag: 'line-$lineId', child: LineBadge(lineId: lineId!)),
                  const SizedBox(height: 16),
                  Text(stations.isEmpty ? '暂无站点目录' : '${stations.first.name} ↔ ${stations.last.name}',
                    style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('${stations.length} 个站点 · 按官方站序排列'),
                  const SizedBox(height: 8),
                  const Text('点击车站查看到站与换乘信息'),
                ]),
              )),
              SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.builder(
                  itemCount: stations.length,
                  itemBuilder: (context, index) {
                    final station = stations[index];
                    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: 32, child: Stack(alignment: Alignment.center, children: [
                        Positioned(top: index == 0 ? 36 : 0, bottom: index == stations.length - 1 ? 36 : 0,
                          child: Container(width: 3, color: LineColors.colorOf(lineId!))),
                        Center(child: Container(width: 16, height: 16,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(color: LineColors.colorOf(lineId!), width: station.lineIds.length > 1 ? 4 : 2)))),
                      ])),
                      Expanded(child: ListTile(
                        minTileHeight: 80,
                        title: Text(station.name),
                        subtitle: station.lineIds.length > 1
                          ? Padding(padding: const EdgeInsets.only(top: 8),
                              child: Wrap(spacing: 6, runSpacing: 6, children: [
                                for (final other in station.lineIds.where((id) => id != lineId))
                                  LineBadge(lineId: other, small: true),
                              ]))
                          : Text(station.pinyin),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/stations/${station.id}'),
                      )),
                    ]));
                  },
                ),
              ),
            ]),
          ));
        },
      ),
    );
  }
}
