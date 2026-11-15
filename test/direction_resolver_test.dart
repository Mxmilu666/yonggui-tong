import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonggui_tong/core/models/station.dart';
import 'package:yonggui_tong/core/utils/direction_resolver.dart';
import 'package:yonggui_tong/core/utils/station_resolver.dart';

void main() {
  late StationCatalog catalog;

  setUp(() {
    final list = jsonDecode(File('test/fixtures/stations.json').readAsStringSync()) as Map;
    final dictionary = parseDictionary((jsonDecode(File('test/fixtures/dict.json').readAsStringSync()) as Map)['Data']);
    catalog = StationCatalog(stations: resolveStations((list['Data']['Items'] as List)
      .map((entry) => StationEntry.fromJson(Map<String, dynamic>.from(entry as Map))).toList(), dictionary),
      dictionary: dictionary, updatedAt: DateTime.utc(2026, 11, 16));
  });

  test('九条线的18个方向与官方站点资料一致，不依赖编码或显示排序', () {
    final reference = jsonDecode(File('test/fixtures/directions.json').readAsStringSync()) as Map;
    final reordered = StationCatalog(stations: catalog.stations.reversed.toList(),
      dictionary: catalog.dictionary, updatedAt: catalog.updatedAt);
    for (final source in reference['sources'] as List) {
      for (final direction in source['StationTimes'] as List) {
        expect(DirectionResolver.label(lineId: direction['LineId'] as int,
          flag: direction['Flag'] as int, catalog: reordered), '往 ${direction['EndStationName']}',
          reason: '${source['url']} · ${direction['LineId']}_${direction['Flag']}');
      }
    }
  });

  test('终点名称取当前API目录，不固化旧名称', () {
    final terminal = catalog.search('霞浦').single;
    final renamed = StationCatalog(stations: [
      for (final station in catalog.stations)
        station.id == terminal.id
          ? Station(id: terminal.id, name: '霞浦（目录更新名称）', entries: terminal.entries) : station,
    ], dictionary: catalog.dictionary, updatedAt: catalog.updatedAt);
    expect(DirectionResolver.label(lineId: 1, flag: 1, catalog: renamed), '往 霞浦（目录更新名称）');
  });

  test('未核实的方向、缺失终点和不一致字典不能标成错误终点', () {
    expect(DirectionResolver.label(lineId: 99, flag: 1, catalog: catalog), '方向 1（终点待确认）');
    expect(DirectionResolver.label(lineId: 1, flag: 3, catalog: catalog), '方向 3（终点待确认）');
    expect(DirectionResolver.label(lineId: 1, flag: 1, catalog: null), '方向 1（终点待确认）');
    final incomplete = StationCatalog(stations: catalog.stations,
      dictionary: {...catalog.dictionary}..remove('0129'), updatedAt: catalog.updatedAt);
    expect(DirectionResolver.label(lineId: 1, flag: 1, catalog: incomplete), '方向 1（终点待确认）');
    final mismatched = StationCatalog(stations: catalog.stations,
      dictionary: {...catalog.dictionary, '0129': catalog.search('鼓楼').single.id}, updatedAt: catalog.updatedAt);
    expect(DirectionResolver.label(lineId: 1, flag: 1, catalog: mismatched), '方向 1（终点待确认）');
  });
}
