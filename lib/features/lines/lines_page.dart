import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/line_colors.dart';
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
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: stations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final station = stations[index];
                return Card(child: ListTile(
                  minTileHeight: 72,
                  leading: CircleAvatar(
                    backgroundColor: LineColors.colorOf(lineId!),
                    foregroundColor: LineColors.onColorOf(lineId!),
                    child: Text('${index + 1}'),
                  ),
                  title: Text(station.name),
                  subtitle: Text(station.lineIds.length > 1
                    ? '换乘 ${station.lineIds.where((id) => id != lineId).map((id) => '$id号线').join(' · ')}'
                    : station.pinyin),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/stations/${station.id}'),
                ));
              },
            ),
          ));
        },
      ),
    );
  }
}
