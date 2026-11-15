import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonggui_tong/core/models/line.dart';
import 'package:yonggui_tong/core/models/station.dart';
import 'package:yonggui_tong/core/utils/station_resolver.dart';
import 'package:yonggui_tong/features/planner/route_planner.dart';

void main() {
  late StationCatalog catalog;
  late MetroNetwork network;
  late RoutePlanner planner;
  int id(String name) => catalog.search(name).single.id;

  setUp(() {
    final list = jsonDecode(File('test/fixtures/stations.json').readAsStringSync()) as Map;
    final dict = parseDictionary((jsonDecode(File('test/fixtures/dict.json').readAsStringSync()) as Map)['Data']);
    catalog = StationCatalog(stations: resolveStations((list['Data']['Items'] as List)
      .map((e) => StationEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList(), dict),
      dictionary: dict, updatedAt: DateTime.utc(2026, 11, 16));
    network = MetroNetwork.fromJson(jsonDecode(File('assets/data/network.json').readAsStringSync()) as Map<String, dynamic>);
    planner = RoutePlanner(network, catalog);
  });

  test('直达按相邻站计时，换乘起点不收换乘惩罚', () {
    final route = planner.estimate(id('鼓楼'), id('宁波火车站'))!;
    expect(route.minutes, 4);
    expect(route.stops, 2);
    expect(route.transfers, 0);
    expect(route.segments.single.lineId, 2);
    expect(route.segments.single.stationIds, [id('鼓楼'), id('城隍庙'), id('宁波火车站')]);
  });

  test('跨线行程返回完整线路段与换乘站，额外计4分钟', () {
    final route = planner.estimate(id('东门口（天一广场）'), id('城隍庙'))!;
    expect(route.minutes, 8);
    expect(route.stops, 2);
    expect(route.transfers, 1);
    expect(route.segments.map((s) => s.lineId), [1, 2]);
    expect(route.segments.first.stationIds.last, id('鼓楼'));
    expect(route.segments.last.stationIds.first, id('鼓楼'));
    final reverse = planner.estimate(route.destinationId, route.originId)!;
    expect(reverse.minutes, route.minutes);
    expect(reverse.segments.map((s) => s.lineId), [2, 1]);
  });

  test('3号线延伸段和12号线站序不被编码打乱', () {
    expect(planner.estimate(id('金海路'), id('大成东路'))!.minutes, 2);
    final route = planner.estimate(id('大目湾'), id('小洋江'))!;
    expect(route.segments.single.lineId, 12);
    expect(route.stops, 9);
    expect(route.minutes, 18);
  });

  test('同站无需乘车，未知站和断开的目录不能虚构直连', () {
    expect(planner.estimate(id('鼓楼'), id('鼓楼'))!.minutes, 0);
    expect(planner.estimate(-1, id('鼓楼')), isNull);
    final a = id('鼓楼'), middle = id('东门口（天一广场）'), b = id('江厦桥东');
    final partialCatalog = StationCatalog(stations: catalog.stations.where((s) => s.id != middle).toList(),
      dictionary: catalog.dictionary, updatedAt: catalog.updatedAt);
    final partial = RoutePlanner(MetroNetwork(lines: [MetroLine(id: 1, name: '1号线',
      stationIds: [a, middle, b])], points: network.points), partialCatalog);
    expect(partial.estimate(a, b), isNull);
  });
}
