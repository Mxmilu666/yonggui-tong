import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/line.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../data/providers.dart';
import '../search/station_search.dart';
import 'route_planner.dart';
import 'planner_page_route_result.dart';

final routePlannerProvider = Provider<AsyncValue<RoutePlanner>>((ref) {
  final catalog = ref.watch(catalogProvider);
  final network = ref.watch(networkProvider);
  if (catalog.valueOrNull case final data?) {
    return network.whenData((graph) => RoutePlanner(graph, data));
  }
  return catalog.hasError ? AsyncError(catalog.error!, catalog.stackTrace ?? StackTrace.current)
      : const AsyncLoading();
});

class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key, this.originId, this.destinationId});
  final int? originId;
  final int? destinationId;

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  late int? _origin = widget.originId;
  late int? _destination = widget.destinationId;

  Future<void> _pick(bool origin) async {
    final station = await showStationSearch(context, ref);
    if (station != null && mounted) {
      setState(() { if (origin) { _origin = station.id; } else { _destination = station.id; } });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogProvider);
    final catalog = catalogState.valueOrNull;
    final planner = ref.watch(routePlannerProvider);
    final from = _origin == null ? null : catalog?.stationById(_origin!);
    final to = _destination == null ? null : catalog?.stationById(_destination!);
    final controls = Card(child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('从哪里，到哪里', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        if (catalogState.isLoading && catalog == null) const LinearProgressIndicator(),
        if (catalogState.hasError) ErrorState(message: '${catalogState.error}',
          onRetry: () => ref.read(catalogProvider.notifier).refresh(force: true)),
        ListTile(contentPadding: EdgeInsets.zero, minTileHeight: 64,
          leading: const Icon(Icons.trip_origin, semanticLabel: '起点'),
          title: Text(from?.name ?? '选择出发站'), subtitle: const Text('起点'),
          trailing: const Icon(Icons.search), onTap: () => _pick(true)),
        Align(alignment: Alignment.centerRight, child: IconButton.filledTonal(
          tooltip: '交换起点与终点', onPressed: () => setState(() {
            final old = _origin; _origin = _destination; _destination = old;
          }), icon: const Icon(Icons.swap_vert))),
        ListTile(contentPadding: EdgeInsets.zero, minTileHeight: 64,
          leading: const Icon(Icons.location_on_outlined, semanticLabel: '终点'),
          title: Text(to?.name ?? '选择目的站'), subtitle: const Text('终点'),
          trailing: const Icon(Icons.search), onTap: () => _pick(false)),
        const SizedBox(height: 16),
        const Text('估算，不含候车/延误\n相邻站 2 分钟 · 每次换乘 4 分钟'),
      ]),
    ));
    final result = from == null || to == null
      ? const EmptyState(title: '先选两站，再出发', message: '按站名、拼音或编码搜索，估算含换乘的行程。', icon: Icons.alt_route)
      : planner.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: LinearProgressIndicator()),
          error: (error, _) => ErrorState(message: '$error', onRetry: () {
            ref.invalidate(networkProvider);
            ref.read(catalogProvider.notifier).refresh();
          }),
          data: (engine) {
            final route = engine.estimate(from.id, to.id);
            return route == null
              ? const EmptyState(title: '未找到连通方案', message: '当前目录与示意线网没有可连接的路径，请选择其他车站。')
              : RouteResult(plan: route, catalog: catalog!);
          },
        );
    return Scaffold(
      appBar: AppBar(title: const Text('行程估算')),
      body: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= 1000) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 360, child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: controls)),
            const VerticalDivider(width: 1),
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: result)),
          ]);
        }
        return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            controls, const SizedBox(height: 24), result,
          ])));
      }),
    );
  }
}

