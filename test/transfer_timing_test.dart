import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonggui_tong/core/models/arrival.dart';
import 'package:yonggui_tong/core/models/line.dart';
import 'package:yonggui_tong/core/models/station.dart';
import 'package:yonggui_tong/core/utils/station_resolver.dart';
import 'package:yonggui_tong/core/utils/transfer_timing.dart';
import 'package:yonggui_tong/features/planner/route_planner.dart';

void main() {
  test('换乘间隔只取行进方向的到站与之后的接续发车', () {
    final list = jsonDecode(File('test/fixtures/stations.json').readAsStringSync()) as Map;
    final dict = parseDictionary((jsonDecode(File('test/fixtures/dict.json').readAsStringSync()) as Map)['Data']);
    final catalog = StationCatalog(stations: resolveStations((list['Data']['Items'] as List)
      .map((e) => StationEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList(), dict),
      dictionary: dict, updatedAt: DateTime.utc(2026, 11, 16));
    final network = MetroNetwork.fromJson(jsonDecode(File('assets/data/network.json').readAsStringSync()) as Map<String, dynamic>);
    int id(String name) => catalog.search(name).single.id;
    // 东门口 -> 鼓楼 runs toward 高桥西 (Flag 2); 鼓楼 -> 城隍庙 runs toward 栎社国际机场 (Flag 2).
    final plan = RoutePlanner(network, catalog).estimate(id('东门口（天一广场）'), id('城隍庙'))!;
    final now = DateTime.utc(2026, 11, 16); // 08:00 Beijing
    final gulou = id('鼓楼');
    ArrivalDirection direction(int line, int flag, List<String> times) => ArrivalDirection(
      lineId: line, flag: flag, stationId: gulou, observedAt: now, runs: [
        for (final (index, time) in times.indexed)
          ArrivalRun(sequence: index + 1, intimeStr: time, outTimeStr: time, intimeDura: 1),
      ]);
    final snapshot = ArrivalSnapshot(stationId: gulou, fetchedAt: now, directions: [
      direction(1, 1, ['08:01:00']),
      direction(1, 2, ['08:05:00']),
      direction(2, 1, ['08:06:00']),
      direction(2, 2, ['08:09:00', '08:04:00']),
    ]);

    final connection = transferConnection(plan: plan, index: 0, snapshot: snapshot, catalog: catalog, now: now)!;

    expect(connection.stationId, gulou);
    expect(connection.arrive.intimeStr, '08:05:00');
    expect(connection.depart.outTimeStr, '08:09:00');
    expect(connection.gap, const Duration(minutes: 4));
    expect(connection.tight, isTrue);
  });
}
