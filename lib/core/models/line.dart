import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'station.dart';

class MetroLine {
  MetroLine({required this.id, required this.name, required List<int> stationIds})
      : stationIds = List.unmodifiable(stationIds);

  factory MetroLine.fromJson(Map<String, dynamic> json) => MetroLine(
    id: json['id'] as int,
    name: json['name'] as String,
    stationIds: (json['stations'] as List).cast<int>(),
  );

  final int id;
  final String name;
  final List<int> stationIds;
}

class NetworkPoint {
  NetworkPoint({required this.id, required this.position, required List<int> lines})
      : lines = List.unmodifiable(lines);
  final int id;
  final Offset position;
  final List<int> lines;
}

class MetroNetwork {
  MetroNetwork({required List<MetroLine> lines, required Map<int, NetworkPoint> points})
      : lines = List.unmodifiable(lines), points = Map.unmodifiable(points);

  factory MetroNetwork.fromJson(Map<String, dynamic> json) {
    final stations = json['stations'] as Map<String, dynamic>;
    return MetroNetwork(
      lines: (json['lines'] as List).map((line) => MetroLine.fromJson(
        Map<String, dynamic>.from(line as Map))).toList(),
      points: stations.map((key, value) {
        final point = value as Map<String, dynamic>;
        final id = int.parse(key);
        return MapEntry(id, NetworkPoint(
          id: id,
          position: Offset((point['x'] as num).toDouble(), (point['y'] as num).toDouble()),
          lines: (point['lines'] as List).cast<int>(),
        ));
      }),
    );
  }

  final List<MetroLine> lines;
  final Map<int, NetworkPoint> points;

  // API membership is authoritative; the asset contributes only geometry/order.
  List<MetroLine> resolvedLines(StationCatalog catalog) => [
    for (final line in lines)
      MetroLine(id: line.id, name: line.name, stationIds: [
        for (final id in line.stationIds)
          if (catalog.stationById(id)?.lineIds.contains(line.id) ?? false) id,
      ]),
  ];
}

final networkProvider = FutureProvider<MetroNetwork>((ref) async {
  final source = await rootBundle.loadString('assets/data/network.json');
  return MetroNetwork.fromJson(jsonDecode(source) as Map<String, dynamic>);
});
