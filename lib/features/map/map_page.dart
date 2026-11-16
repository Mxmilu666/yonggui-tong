import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/line_colors.dart';
import '../../core/models/line.dart';
import '../../core/models/station.dart';
import '../../data/providers.dart';
import '../../core/widgets/line_badge.dart';
import '../arrivals/arrivals_page.dart';
import 'network_painter.dart';

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  final _transform = TransformationController();
  int? _selectedLine;
  Size? _viewport;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _reset(Size size) {
    final scale = math.min(size.width / NetworkPainter.canvasSize.width,
      size.height / NetworkPainter.canvasSize.height) * .9;
    final dx = (size.width - NetworkPainter.canvasSize.width * scale) / 2;
    final dy = (size.height - NetworkPainter.canvasSize.height * scale) / 2;
    _transform.value = Matrix4.identity()..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _zoom(double factor) {
    final size = _viewport;
    if (size == null) return;
    final current = _transform.value.entry(0, 0).abs();
    final next = (current * factor).clamp(.08, 3.0);
    final center = Offset(size.width / 2, size.height / 2);
    final world = _transform.toScene(center);
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx - world.dx * next, center.dy - world.dy * next, 0, 1)
      ..scaleByDouble(next, next, next, 1);
  }

  Future<void> _showStation(int id) async {
    final station = ref.read(catalogProvider).valueOrNull?.stationById(id);
    if (station == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(station.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final line in station.lineIds) LineBadge(lineId: line),
              ]),
              const SizedBox(height: 16),
              ArrivalBoard(stationId: id, compact: true),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  context.push('/stations/$id');
                },
                icon: const Icon(Icons.arrow_forward), label: const Text('查看详情'),
              ),
            ],
          )),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final network = ref.watch(networkProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('探索线网'),
        actions: [
          IconButton(onPressed: () => context.push('/planner'),
            tooltip: '行程估算', icon: const Icon(Icons.alt_route)),
          IconButton(onPressed: () => context.push('/lines'),
            tooltip: '线路列表', icon: const Icon(Icons.format_list_bulleted)),
        ],
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _failure('站点目录加载失败',
          () => ref.read(catalogProvider.notifier).refresh()),
        data: (data) => network.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _failure('示意线网加载失败', () => ref.invalidate(networkProvider)),
          data: (graph) => Column(children: [
            SizedBox(height: 64, child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              scrollDirection: Axis.horizontal,
              children: [
                Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(
                  label: const Text('全部线路'), selected: _selectedLine == null,
                  onSelected: (_) => setState(() => _selectedLine = null),
                )),
                for (final id in LineColors.ids)
                  Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(
                    label: Text('$id号线'),
                    avatar: CircleAvatar(backgroundColor: LineColors.colorOf(id), radius: 6),
                    selected: _selectedLine == id,
                    onSelected: (selected) => setState(() => _selectedLine = selected ? id : null),
                  )),
              ],
            )),
            Expanded(child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              return Row(children: [
                Expanded(child: _canvas(data, graph)),
                if (wide) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 300, child: _stationList(data)),
                ],
              ]);
            })),
            const Divider(height: 1),
            Padding(padding: const EdgeInsets.all(12), child: Wrap(
              alignment: WrapAlignment.center, spacing: 16, runSpacing: 8,
              children: const [
                Text('○ 普通站  ◉ 换乘站'),
                Text('示意图，非地理比例'),
                Text('放大查看站名 · 点击站点查看到站'),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  Widget _failure(String message, VoidCallback retry) => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [Text(message), const SizedBox(height: 16),
      FilledButton.tonal(onPressed: retry, child: const Text('重试'))],
  ));

  Widget _stationList(StationCatalog data) {
    final stations = _selectedLine == null
        ? data.stations.where((station) => station.lineIds.length > 1).toList()
        : data.stationsForLine(_selectedLine!);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(_selectedLine == null ? '换乘枢纽' : '$_selectedLine号线',
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text('${stations.length} 个站点 · 点击查看到站'),
      const SizedBox(height: 16),
      for (final station in stations)
        ListTile(title: Text(station.name),
          subtitle: Text(station.lineIds.map((id) => '$id号线').join(' · ')),
          trailing: const Icon(Icons.chevron_right), onTap: () => _showStation(station.id)),
    ]);
  }

  Widget _canvas(StationCatalog catalog, MetroNetwork network) =>
    LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (_viewport != size) {
        _viewport = size;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _viewport == size) _reset(size);
        });
      }
      return ClipRect(child: Stack(children: [
        Positioned.fill(child: InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          minScale: .08,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(1000),
          child: AnimatedBuilder(animation: _transform, builder: (context, _) {
            final scale = _transform.value.entry(0, 0).abs();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                NetworkPoint? nearest;
                var distance = 24 / scale;
                for (final point in network.points.values) {
                  final station = catalog.stationById(point.id);
                  if (station == null || (_selectedLine != null &&
                      !station.lineIds.contains(_selectedLine))) {
                    continue;
                  }
                  final d = (point.position - details.localPosition).distance;
                  if (d < distance) { distance = d; nearest = point; }
                }
                if (nearest != null) _showStation(nearest.id);
              },
              child: CustomPaint(
                size: NetworkPainter.canvasSize,
                painter: NetworkPainter(network: network, catalog: catalog,
                  selectedLine: _selectedLine, scale: scale,
                  scheme: Theme.of(context).colorScheme, onStationTap: _showStation),
              ),
            );
          }),
        )),
        Positioned(right: 16, bottom: 16, child: Card(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(onPressed: () => _zoom(1.5), tooltip: '放大线网', icon: const Icon(Icons.add)),
            IconButton(onPressed: () => _zoom(1 / 1.5), tooltip: '缩小线网', icon: const Icon(Icons.remove)),
            IconButton(onPressed: () => _reset(size), tooltip: '重置视图', icon: const Icon(Icons.center_focus_strong)),
          ],
        ))),
      ]));
    });
}
