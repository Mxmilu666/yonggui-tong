import '../utils/station_resolver.dart';

class StationEntry {
  const StationEntry({required this.rank, required this.pinyin, required this.line,
    required this.letter, required this.name, required this.code});
  factory StationEntry.fromJson(Map<String, dynamic> json) => StationEntry(
    rank: (json['Rank'] as num).toInt(), pinyin: json['Pinyin'] as String,
    line: json['Line'] as String, letter: json['Letter'] as String,
    name: json['Name'] as String, code: json['Code'] as String);
  final int rank;
  final String pinyin, line, letter, name, code;
  Map<String, dynamic> toJson() => {'Rank': rank, 'Pinyin': pinyin,
    'Line': line, 'Letter': letter, 'Name': name, 'Code': code};
}

class Station {
  Station({required this.id, required this.name, required List<StationEntry> entries})
      : entries = List.unmodifiable(entries);
  final int id;
  final String name;
  final List<StationEntry> entries;
  late final List<int> _lineIds = List.unmodifiable(
    entries.map((entry) => lineIdOf(entry.line)).toSet().toList()..sort());
  late final List<String> _codes = List.unmodifiable(entries.map((entry) => entry.code));
  List<int> get lineIds => _lineIds;
  String get pinyin => entries.first.pinyin;
  List<String> get codes => _codes;
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return name.contains(q) || entries.any((e) => e.pinyin.toLowerCase().contains(q)
      || e.letter.toLowerCase().contains(q) || e.code.contains(q));
  }
}

class StationCatalog {
  StationCatalog({required List<Station> stations, required Map<String, int> dictionary,
    required this.updatedAt}) : stations = List.unmodifiable(stations),
    dictionary = Map.unmodifiable(dictionary);
  final List<Station> stations;
  final Map<String, int> dictionary;
  final DateTime updatedAt;
  late final Map<int, Station> _byId = {for (final station in stations) station.id: station};
  Station? stationById(int id) => _byId[id];
  List<Station> search(String query) {
    final q = query.trim().toLowerCase();
    final line = RegExp(r'^(?:地铁\s*)?([1-9]\d?)\s*号线(?:路)?$').firstMatch(q)
        ?? RegExp(r'^line\s*([1-9]\d?)$').firstMatch(q)
        ?? RegExp(r'^([1-9]\d?)$').firstMatch(q);
    if (line != null) return stationsForLine(int.parse(line[1]!));
    return stations.where((s) => s.matches(q)).toList();
  }
  List<Station> stationsForLine(int id) {
    final result = stations.where((s) => s.lineIds.contains(id)).toList();
    int rank(Station s) => s.entries.firstWhere((e) => lineIdOf(e.line) == id).rank;
    result.sort((a, b) => rank(a).compareTo(rank(b)));
    return result;
  }
  List<int> get lineIds => (stations.expand((s) => s.lineIds).toSet().toList()..sort());
}
