import '../utils/time_utils.dart';

class ArrivalRun {
  const ArrivalRun({required this.sequence, required this.intimeStr,
    required this.outTimeStr, required this.intimeDura});
  factory ArrivalRun.fromJson(Map<String, dynamic> json) => ArrivalRun(
    sequence: (json['Sequence'] as num).toInt(), intimeStr: json['IntimeStr'] as String,
    outTimeStr: json['OutTimeStr'] as String, intimeDura: json['IntimeDura'] as num);
  final int sequence;
  final String intimeStr, outTimeStr;
  final num intimeDura;
}

class ArrivalDirection {
  ArrivalDirection({required this.lineId, required this.flag, required this.stationId,
    required List<ArrivalRun> runs, DateTime? observedAt})
    : runs = List.unmodifiable(runs), observedAt = observedAt ?? DateTime.now().toUtc();
  factory ArrivalDirection.fromJson(Map<String, dynamic> json, {DateTime? observedAt}) =>
    ArrivalDirection(lineId: (json['LineId'] as num).toInt(),
      flag: (json['Flag'] as num).toInt(), stationId: (json['StationId'] as num).toInt(),
      observedAt: observedAt, runs: (json['StationRunTimes'] as List)
        .map((e) => ArrivalRun.fromJson(Map<String, dynamic>.from(e as Map))).toList());
  final int lineId, flag, stationId;
  final List<ArrivalRun> runs;
  final DateTime observedAt;
  List<ArrivalRun> validRuns(DateTime now) {
    // Anchor the day to receipt time, never resurrect a cached timetable tomorrow.
    if (now.toUtc().difference(observedAt.toUtc()) >= const Duration(hours: 6)) return [];
    return runs.where((run) => TimeUtils.remaining(run.intimeStr, now,
      intimeDura: run.intimeDura) != null).toList();
  }
}

class ArrivalSnapshot {
  ArrivalSnapshot({required this.stationId, required List<ArrivalDirection> directions,
    required this.fetchedAt}) : directions = List.unmodifiable(directions);
  final int stationId;
  final List<ArrivalDirection> directions;
  final DateTime fetchedAt;
}
