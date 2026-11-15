import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/station.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/error_state.dart';
import '../../data/providers.dart';
import '../arrivals/arrivals_page.dart';

class StationPage extends ConsumerWidget {
  const StationPage({super.key, required this.stationId});
  final int stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final station = catalog.valueOrNull?.stationById(stationId);
    final favorites = ref.watch(favoritesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('站点详情'), actions: [
        if (station != null) IconButton(
          tooltip: favorites.contains(stationId) ? '取消收藏' : '收藏车站',
          icon: Icon(favorites.contains(stationId) ? Icons.star_rounded : Icons.star_outline),
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
      ]),
      body: station == null
        ? catalog.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(child: ErrorState(message: catalog.hasError
              ? '${catalog.error}' : '未找到此车站，请返回重新选择',
              onRetry: () => ref.read(catalogProvider.notifier).refresh(force: true)))
        : RefreshIndicator(
          onRefresh: () => ref.read(arrivalsProvider(stationId).notifier).refresh(),
          child: LayoutBuilder(builder: (context, constraints) {
            final info = _StationInformation(station: station);
            if (constraints.maxWidth >= 1000) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 360, child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24), child: info)),
                const VerticalDivider(width: 1),
                Expanded(child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: ArrivalBoard(stationId: stationId))),
              ]);
            }
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    info, const SizedBox(height: 24), ArrivalBoard(stationId: stationId),
                  ])),
              )),
            );
          }),
        ),
    );
  }
}

class _StationInformation extends StatelessWidget {
  const _StationInformation({required this.station});
  final Station station;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Hero(tag: 'station-${station.id}', child: Material(color: Colors.transparent,
        child: Text(station.name, style: Theme.of(context).textTheme.headlineMedium))),
      const SizedBox(height: 8),
      Text(station.pinyin, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 16),
      Text('站点编码 ${station.codes.join(' / ')}'),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final id in station.lineIds) LineBadge(lineId: id),
      ]),
      const SizedBox(height: 24),
      Text(station.lineIds.length > 1 ? '站内换乘' : '所属线路',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final id in station.lineIds)
        ListTile(contentPadding: EdgeInsets.zero, minTileHeight: 56,
          title: Text('$id号线'), trailing: const Icon(Icons.arrow_forward),
          onTap: () => context.push('/lines/$id')),
    ]),
  ));
}
