import 'package:collection/collection.dart';

import '../../core/models/line.dart';
import '../../core/models/route_plan.dart';
import '../../core/models/station.dart';

typedef _Node = ({int station, int line});
typedef _Edge = ({_Node to, int minutes});
typedef _Visit = ({_Node node, int minutes, int transfers});

class RoutePlanner {
  RoutePlanner(MetroNetwork network, StationCatalog catalog) {
    final membership = {for (final station in catalog.stations) station.id: station.lineIds};
    for (final line in network.lines) {
      bool valid(int id) => membership[id]?.contains(line.id) ?? false;
      for (final id in line.stationIds.where(valid)) {
        _edges.putIfAbsent((station: id, line: line.id), () => []);
      }
      for (var i = 1; i < line.stationIds.length; i++) {
        final a = line.stationIds[i - 1], b = line.stationIds[i];
        // A missing API station must never create a shortcut through a stale asset.
        if (!valid(a) || !valid(b)) continue;
        _connect((station: a, line: line.id), (station: b, line: line.id), 2);
      }
    }
    final byStation = <int, List<_Node>>{};
    for (final node in _edges.keys) {
      byStation.putIfAbsent(node.station, () => []).add(node);
    }
    for (final nodes in byStation.values) {
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          _connect(nodes[i], nodes[j], 4);
        }
      }
    }
    _byStation = byStation;
  }

  final _edges = <_Node, List<_Edge>>{};
  late final Map<int, List<_Node>> _byStation;

  void _connect(_Node a, _Node b, int minutes) {
    _edges[a]!.add((to: b, minutes: minutes));
    _edges[b]!.add((to: a, minutes: minutes));
  }

  RoutePlan? estimate(int originId, int destinationId) {
    if (!_byStation.containsKey(originId) || !_byStation.containsKey(destinationId)) return null;
    if (originId == destinationId) {
      return RoutePlan(originId: originId, destinationId: destinationId, segments: [], minutes: 0);
    }
    final distances = <_Node, (int, int)>{};
    final previous = <_Node, _Node>{};
    final queue = HeapPriorityQueue<_Visit>((a, b) {
      final time = a.minutes.compareTo(b.minutes);
      return time != 0 ? time : a.transfers.compareTo(b.transfers);
    });
    for (final node in _byStation[originId]!) {
      distances[node] = (0, 0);
      queue.add((node: node, minutes: 0, transfers: 0));
    }
    _Visit? end;
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (distances[current.node] != (current.minutes, current.transfers)) continue;
      if (current.node.station == destinationId) { end = current; break; }
      for (final edge in _edges[current.node]!) {
        final minutes = current.minutes + edge.minutes;
        final transfers = current.transfers + (current.node.line == edge.to.line ? 0 : 1);
        final old = distances[edge.to];
        if (old != null && (old.$1 < minutes || old.$1 == minutes && old.$2 <= transfers)) continue;
        distances[edge.to] = (minutes, transfers);
        previous[edge.to] = current.node;
        queue.add((node: edge.to, minutes: minutes, transfers: transfers));
      }
    }
    if (end == null) return null;
    final path = <_Node>[end.node];
    while (previous.containsKey(path.last)) { path.add(previous[path.last]!); }
    final ordered = path.reversed.toList();
    final segments = <RouteSegment>[];
    var line = ordered.first.line;
    var stations = <int>[ordered.first.station];
    for (final node in ordered.skip(1)) {
      if (node.line != line) {
        if (stations.length > 1) segments.add(RouteSegment(lineId: line, stationIds: stations));
        line = node.line;
        stations = [node.station];
      } else if (node.station != stations.last) {
        stations.add(node.station);
      }
    }
    if (stations.length > 1) segments.add(RouteSegment(lineId: line, stationIds: stations));
    return RoutePlan(originId: originId, destinationId: destinationId,
      segments: segments, minutes: end.minutes);
  }
}
