import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonggui_tong/core/models/line.dart';
import 'package:yonggui_tong/core/models/station.dart';
import 'package:yonggui_tong/core/utils/station_resolver.dart';

void main() {
  test('示意线网覆盖真实目录全部站点，顺序与换乘关系由 Dict 和 Rank 确认', () {
    final raw = jsonDecode(File('assets/data/network.json').readAsStringSync()) as Map<String, dynamic>;
    final network = MetroNetwork.fromJson(raw);
    final list = jsonDecode(File('test/fixtures/stations.json').readAsStringSync()) as Map;
    final dict = parseDictionary((jsonDecode(File('test/fixtures/dict.json').readAsStringSync()) as Map)['Data']);
    final entries = (list['Data']['Items'] as List)
      .map((e) => StationEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final catalog = StationCatalog(stations: resolveStations(entries, dict), dictionary: dict,
      updatedAt: DateTime.utc(2026, 11, 16));
    expect(network.lines.map((line) => line.id), catalog.lineIds);
    expect(network.points.keys.toSet(), catalog.stations.map((s) => s.id).toSet());
    for (final line in network.resolvedLines(catalog)) {
      expect(line.stationIds, catalog.stationsForLine(line.id).map((s) => s.id),
        reason: '${line.name} 不能按编码排序或漏掉延伸段');
      for (final id in line.stationIds) {
        expect(network.points[id]!.lines, contains(line.id));
      }
    }
    final gulou = catalog.search('鼓楼').single;
    expect(network.points[gulou.id]!.lines, [1, 2]);
    final xiaoyangjiang = catalog.search('小洋江').single;
    expect(network.points[xiaoyangjiang.id]!.lines, [4, 7, 12]);
  });
}
