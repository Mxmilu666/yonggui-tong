import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/station.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';
import '../arrivals/arrivals_page.dart';

class StationPage extends ConsumerWidget {
  const StationPage({super.key, required this.stationId});
  final int stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final data = catalog.valueOrNull;
    final station = data?.stationById(stationId);
    final favorite = ref.watch(favoritesProvider).contains(stationId);
    return Scaffold(
      appBar: AppBar(actions: [
        if (station != null) IconButton(
          tooltip: favorite ? '取消收藏' : '收藏车站',
          isSelected: favorite,
          icon: const Icon(Icons.star_outline_rounded),
          selectedIcon: const Icon(Icons.star_rounded),
          onPressed: () async {
            try { await ref.read(favoritesProvider.notifier).toggle(stationId); }
            catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('收藏保存失败，请重试')));
              }
            }
          },
        ),
        const SizedBox(width: 4),
      ]),
      body: station == null
        ? catalog.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(child: Padding(padding: const EdgeInsets.all(16), child: ErrorState(message: catalog.hasError
              ? '${catalog.error}' : '未找到此车站，请返回重新选择',
              onRetry: () => ref.read(catalogProvider.notifier).refresh(force: true))))
        : RefreshIndicator(
          onRefresh: () => ref.read(arrivalsProvider(stationId).notifier).refresh(),
          child: LayoutBuilder(builder: (context, constraints) {
            final info = _StationInformation(station: station, catalog: data!);
            final board = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('到站', style: Theme.of(context).textTheme.titleMedium),
              ArrivalBoard(stationId: stationId),
            ]);
            if (constraints.maxWidth >= 1000) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 380, child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24), child: info)),
                const VerticalDivider(width: 1),
                Expanded(child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: board)),
              ]);
            }
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    info, const SizedBox(height: 28), board,
                  ])),
              )),
            );
          }),
        ),
    );
  }
}

class _StationInformation extends StatelessWidget {
  const _StationInformation({required this.station, required this.catalog});
  final Station station;
  final StationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Hero(tag: 'station-${station.id}', child: Material(type: MaterialType.transparency,
        child: Text(station.name, style: text.headlineMedium))),
      const SizedBox(height: 4),
      Text(station.pinyin, style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant)),
      const SizedBox(height: 2),
      Text('站点编码 ${station.codes.join(' / ')}', style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      const SizedBox(height: 16),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final id in station.lineIds) LineBadge(lineId: id),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(onPressed: () => context.push('/planner?from=${station.id}'),
          icon: const Icon(Icons.trip_origin), label: const Text('从这里出发')),
        OutlinedButton.icon(onPressed: () => context.push('/planner?to=${station.id}'),
          icon: const Icon(Icons.place_outlined), label: const Text('到这里去')),
      ]),
      const SizedBox(height: 28),
      Text(station.lineIds.length > 1 ? '站内换乘' : '所属线路', style: text.titleMedium),
      const SizedBox(height: 8),
      Card.outlined(child: Column(children: [
        for (final (index, id) in station.lineIds.indexed) ...[
          if (index > 0) const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: LineAvatar(lineId: id),
            title: Text('$id号线'),
            subtitle: Text(_terminals(id)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/lines/$id'),
          ),
        ],
      ])),
    ]);
  }

  String _terminals(int lineId) {
    final stations = catalog.stationsForLine(lineId);
    return stations.isEmpty ? '暂无目录数据' : '${stations.first.name} ↔ ${stations.last.name}';
  }
}
