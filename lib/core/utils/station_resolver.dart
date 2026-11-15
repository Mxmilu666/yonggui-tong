import 'dart:convert';
import '../models/station.dart';

int lineIdOf(String identifier) {
  const lines = {'0101': 1, '0201': 2, '0301': 3, '0401': 4,
    '0501': 5, '0601': 6, '0701': 7, '0801': 8, '1201': 12};
  final id = lines[identifier];
  if (id == null) throw FormatException('未知线路标识：$identifier');
  return id;
}

Map<String, int> parseDictionary(Object? data) {
  if (data is String) data = jsonDecode(data);
  if (data is! Map) throw const FormatException('站点字典格式错误');
  final result = <String, int>{};
  for (final entry in data.entries) {
    final id = int.tryParse(entry.value.toString());
    if (id == null || id <= 0) throw const FormatException('站点 ID 无效');
    result[entry.key.toString()] = id;
  }
  if (result.isEmpty) throw const FormatException('站点字典为空');
  return Map.unmodifiable(result);
}

List<Station> resolveStations(List<StationEntry> entries, Map<String, int> dictionary) {
  final groups = <int, List<StationEntry>>{};
  for (final entry in entries) {
    final id = dictionary[entry.code];
    if (id == null) throw FormatException('字典缺少站点：${entry.code}');
    lineIdOf(entry.line);
    groups.putIfAbsent(id, () => []).add(entry);
  }
  return groups.entries.map((e) => Station(id: e.key,
    name: e.value.first.name, entries: e.value)).toList(growable: false);
}
