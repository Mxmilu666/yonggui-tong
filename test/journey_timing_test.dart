import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonggui_tong/core/models/arrival.dart';
import 'package:yonggui_tong/core/models/line.dart';
import 'package:yonggui_tong/core/models/route_plan.dart';
import 'package:yonggui_tong/core/models/station.dart';
import 'package:yonggui_tong/core/utils/journey_timing.dart';
import 'package:yonggui_tong/core/utils/station_resolver.dart';
import 'package:yonggui_tong/features/planner/route_planner.dart';

void main() {
  late StationCatalog catalog;
  late RoutePlan plan;
  late int origin, gulou;
  final now = DateTime.utc(2026, 11, 16); // 08:00 Beijing
  DateTime beijing(int h, int m, int s) => DateTime.utc(2026, 11, 16, h - 8, m, s);

  ArrivalSnapshot station(int id, List<(int line, int flag, List<String> times)> directions) =>
    ArrivalSnapshot(stationId: id, fetchedAt: now, directions: [
      for (final (line, flag, times) in directions) ArrivalDirection(lineId: line, flag: flag,
        stationId: id, observedAt: now, runs: [
          for (final (index, time) in times.indexed)
            ArrivalRun(sequence: index + 1, intimeStr: time, outTimeStr: time, intimeDura: 1),
        ]),
    ]);

  setUp(() {
    final list = jsonDecode(File('test/fixtures/stations.json').readAsStringSync()) as Map;
    final dict = parseDictionary((jsonDecode(File('test/fixtures/dict.json').readAsStringSync()) as Map)['Data']);
    catalog = StationCatalog(stations: resolveStations((list['Data']['Items'] as List)
      .map((e) => StationEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList(), dict),
      dictionary: dict, updatedAt: now);
    final network = MetroNetwork.fromJson(jsonDecode(File('assets/data/network.json').readAsStringSync()) as Map<String, dynamic>);
    origin = catalog.search('东门口（天一广场）').single.id;
    gulou = catalog.search('鼓楼').single.id;
    // 东门口 -1 stop-> 鼓楼 on line 1 toward 高桥西 (Flag 2), then 鼓楼 -1 stop-> 城隍庙 on line 2
    // toward 栎社国际机场 (Flag 2).
    plan = RoutePlanner(network, catalog).estimate(origin, catalog.search('城隍庙').single.id)!;
  });

  test('到站对齐换乘站同向来车，接续取之后首班同向去车', () {
    final timing = journeyTiming(plan: plan, catalog: catalog, now: now, snapshots: {
      origin: station(origin, [(1, 1, ['08:01:40']), (1, 2, ['08:02:40'])]),
      gulou: station(gulou, [
        (1, 1, ['08:04:30']),
        (1, 2, ['08:00:30', '08:05:10']), // the train boarded at 08:02:40, estimated 08:04:40
        (2, 1, ['08:05:30']),
        (2, 2, ['08:07:00', '08:04:00']),
      ]),
    })!;

    expect(timing.board, beijing(8, 2, 40));
    final transfer = timing.transfers.single;
    expect(transfer.arriveAt, beijing(8, 5, 10));
    expect(transfer.depart, (at: beijing(8, 7, 0), projected: false));
    expect(transfer.hurry, Hurry.risky); // 1 min 50 s
    // The listed 3-minute headway gives the fallback train.
    expect(transfer.nextDepart, (at: beijing(8, 10, 0), projected: true));
    expect(timing.arriveAt, beijing(8, 9, 0));
  });

  test('估算到站晚于已公布班次时按发车间隔推算出要不要赶', () {
    final timing = journeyTiming(plan: plan, catalog: catalog, now: now, snapshots: {
      origin: station(origin, [(1, 2, ['08:02:40'])]),
      gulou: station(gulou, [(2, 2, ['08:01:00', '08:04:00'])]),
    })!;

    final transfer = timing.transfers.single;
    expect(transfer.arriveAt, beijing(8, 4, 40)); // no incoming times listed: ride estimate
    expect(transfer.depart, (at: beijing(8, 7, 0), projected: true));
    expect(transfer.hurry, Hurry.hurry);
    expect(timing.hurry, Hurry.hurry);
  });

  test('只有一班可参照时不外推', () {
    final timing = journeyTiming(plan: plan, catalog: catalog, now: now, snapshots: {
      origin: station(origin, [(1, 2, ['08:02:40'])]),
      gulou: station(gulou, [(2, 2, ['08:03:00'])]),
    })!;

    final transfer = timing.transfers.single;
    expect(transfer.status, TransferStatus.beyondSchedule);
    expect(transfer.lastKnown, beijing(8, 3, 0));
    expect(transfer.depart, isNull);
    expect(timing.arriveAt, isNull);
  });
}
