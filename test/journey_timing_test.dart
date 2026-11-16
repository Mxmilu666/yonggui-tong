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
import 'package:yonggui_tong/core/utils/live_stages.dart';

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
            ArrivalRun(sequence: index + 1, intimeStr: time, outTimeStr: time, intimeDura: 1, outTimeDura: 1),
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

  test('现在出发仍选择已到站但未发车的列车，等车通知保持到离站', () {
    final observed = now.subtract(const Duration(minutes: 1));
    final atPlatform = ArrivalSnapshot(stationId: origin, fetchedAt: observed, directions: [
      ArrivalDirection(lineId: 1, flag: 2, stationId: origin, observedAt: observed, runs: [
        const ArrivalRun(sequence: 1, intimeStr: '07:59:50', outTimeStr: '08:00:35', intimeDura: 50, outTimeDura: 95),
        const ArrivalRun(sequence: 2, intimeStr: '08:03:00', outTimeStr: '08:03:45', intimeDura: 240, outTimeDura: 285),
      ]),
    ]);
    final timing = journeyTiming(plan: plan, catalog: catalog, now: now, snapshots: {origin: atPlatform})!;
    expect(timing.board, beijing(8, 0, 35));
    final stop = atPlatform.directions.single.upcoming(now).first;
    final waiting = waitForTrain(station: catalog.stationById(origin)!, lineId: 1, direction: '往 高桥西',
      scheduled: stop, now: observed);
    expect(waiting.stages.first.countdownTo, beijing(7, 59, 50));
    expect(waiting.stages.last.at, beijing(7, 59, 50));
    expect(waiting.stages.last.countdownTo, beijing(8, 0, 35));
    expect(waiting.endsAt, beijing(8, 0, 35));
    final duringDwell = waitForTrain(station: catalog.stationById(origin)!, lineId: 1, direction: '往 高桥西',
      scheduled: stop, now: now);
    expect(duringDwell.stages.single.countdownTo, stop.departAt);
    expect(duringDwell.stages.single.text, contains('停靠中'));
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

  test('行程实时更新按上车、乘车、换乘、到达切换，换乘阶段倒计时到接续发车', () {
    final timing = journeyTiming(plan: plan, catalog: catalog, now: now, snapshots: {
      origin: station(origin, [(1, 2, ['08:02:40'])]),
      gulou: station(gulou, [(1, 2, ['08:05:10']), (2, 2, ['08:04:00', '08:07:00'])]),
    })!;

    final trip = journeyTrip(plan: plan, timing: timing, catalog: catalog, now: now)!;

    expect([for (final s in trip.stages) (s.at, s.title, s.countdownTo)], [
      (now, '东门口（天一广场） → 城隍庙', beijing(8, 2, 40)),
      (beijing(8, 2, 40), '乘坐 1号线 往 高桥西', beijing(8, 5, 10)),
      (beijing(8, 5, 10), '鼓楼换乘 · 可能赶不上', beijing(8, 7, 0)),
      (beijing(8, 7, 0), '乘坐 2号线 往 栎社国际机场', beijing(8, 9, 0)),
    ]);
    expect(trip.stages[2].text, '2号线 往 栎社国际机场 08:07:00 开，错过则下一班 约 08:10');
    expect(trip.endsAt, beijing(8, 11, 0));
  });

  test('换乘班次推算不出时，行程在换乘站停下并提示看站台', () {
    final timing = journeyTiming(plan: plan, catalog: catalog, now: now, snapshots: {
      origin: station(origin, [(1, 2, ['08:02:40'])]),
      gulou: station(gulou, [(2, 2, ['08:03:00'])]),
    })!;

    final trip = journeyTrip(plan: plan, timing: timing, catalog: catalog, now: now)!;

    expect(trip.stages.last.title, '鼓楼换乘');
    expect(trip.stages.last.countdownTo, isNull);
    expect(trip.endsAt, beijing(8, 34, 40)); // estimated arrival 08:04:40 + 30 min
  });
}
