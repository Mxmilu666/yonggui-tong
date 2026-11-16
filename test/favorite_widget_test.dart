import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonggui_tong/core/models/station.dart';
import 'package:yonggui_tong/core/utils/station_resolver.dart';
import 'package:yonggui_tong/data/favorite_widget.dart';

void main() {
  test('桌面小组件收到 Dict 解析后的站点 ID 和各方向终点', () {
    final list = jsonDecode(File('test/fixtures/stations.json').readAsStringSync()) as Map;
    final dict = parseDictionary((jsonDecode(File('test/fixtures/dict.json').readAsStringSync()) as Map)['Data']);
    final catalog = StationCatalog(stations: resolveStations((list['Data']['Items'] as List)
      .map((e) => StationEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList(), dict),
      dictionary: dict, updatedAt: DateTime.utc(2026, 11, 16));

    final payload = jsonDecode(favoriteWidgetPayload([catalog.search('鼓楼').single], catalog)) as List;

    final gulou = payload.single as Map;
    expect(gulou['id'], 16); // 0110 / 0242 -> 16, never a raw Code
    expect([for (final d in gulou['directions'] as List) '${d['line']}_${d['flag']} ${d['label']}'], [
      '1_1 往 霞浦', '1_2 往 高桥西', '2_1 往 红联', '2_2 往 栎社国际机场',
    ]);
    expect((gulou['directions'] as List).first['color'], 0xFF138FC9);
  });
}
