import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/line.dart';
import '../../core/models/station.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../data/providers.dart';
import '../search/station_search.dart';
import 'planner_page_route_result.dart';
import 'route_planner.dart';

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
    final controls = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (catalogState.isLoading && catalog == null) const LinearProgressIndicator(),
      if (catalogState.hasError) ...[
        ErrorState(message: '${catalogState.error}',
          onRetry: () => ref.read(catalogProvider.notifier).refresh(force: true)),
        const SizedBox(height: 12),
      ],
      Card.filled(child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
        child: Row(children: [
          Expanded(child: Column(children: [
            _Endpoint(label: '起点', placeholder: '选择出发站', station: from,
              icon: Icons.trip_origin, onTap: () => _pick(true)),
            const Divider(indent: 56),
            _Endpoint(label: '终点', placeholder: '选择目的站', station: to,
              icon: Icons.place_outlined, onTap: () => _pick(false)),
          ])),
          IconButton(
            tooltip: '交换起点与终点',
            onPressed: () => setState(() {
              final old = _origin; _origin = _destination; _destination = old;
            }),
            icon: const Icon(Icons.swap_vert),
          ),
        ]),
      )),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text('相邻站约 2 分钟、每次换乘约 4 分钟的本地估算，不含候车与延误。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
    ]);
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
            SizedBox(width: 380, child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: controls)),
            const VerticalDivider(width: 1),
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: result)),
          ]);
        }
        return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            controls, const SizedBox(height: 24), result,
          ])));
      }),
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({required this.label, required this.placeholder, required this.station,
    required this.icon, required this.onTap});
  final String label;
  final String placeholder;
  final Station? station;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListTile(
      minTileHeight: 64,
      leading: Icon(icon, color: colors.primary, semanticLabel: label),
      title: Text(label, style: text.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
      subtitle: Text(station?.name ?? placeholder, style: text.titleMedium?.copyWith(
        color: station == null ? colors.onSurfaceVariant : colors.onSurface)),
      onTap: onTap,
    );
  }
}
