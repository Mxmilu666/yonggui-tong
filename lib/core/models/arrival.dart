import '../utils/time_utils.dart';

class ArrivalRun {
  const ArrivalRun({required this.sequence, required this.intimeStr,
    required this.outTimeStr, required this.intimeDura, required this.outTimeDura});
  factory ArrivalRun.fromJson(Map<String, dynamic> json) => ArrivalRun(
    sequence: (json['Sequence'] as num).toInt(), intimeStr: json['IntimeStr'] as String,
    outTimeStr: json['OutTimeStr'] as String, intimeDura: json['IntimeDura'] as num,
    outTimeDura: json['OutTimeDura'] as num);
  final int sequence;
  final String intimeStr, outTimeStr;
  final num intimeDura, outTimeDura;

  ScheduledRun? scheduled(DateTime observedAt) {
    // A train may already be at the platform (IntimeDura <= 0) but still boardable.
    // The API's no-service sentinel has both durations negative.
    if (!intimeDura.isFinite || !outTimeDura.isFinite || outTimeDura <= 0) return null;
    final departAt = TimeUtils.departure(outTimeStr, observedAt);
    if (departAt == null) return null;
    var arriveAt = TimeUtils.clockOnDay(intimeStr, departAt);
    if (arriveAt == null) return null;
    if (arriveAt.isAfter(departAt)) {
      final arrivalHour = arriveAt.add(const Duration(hours: 8)).hour;
      final departureHour = departAt.add(const Duration(hours: 8)).hour;
      if (arrivalHour < 18 || departureHour >= 6) return null;
      arriveAt = arriveAt.subtract(const Duration(days: 1));
    }
    if (departAt.difference(arriveAt) >= const Duration(hours: 6)) return null;
    return ScheduledRun(run: this, arriveAt: arriveAt, departAt: departAt);
  }
}

/// Published stop window, not a live position report. Ends exclusively at departure.
class ScheduledRun {
  const ScheduledRun({required this.run, required this.arriveAt, required this.departAt});
  final ArrivalRun run;
  final DateTime arriveAt, departAt;
  bool isDwelling(DateTime now) => !now.isBefore(arriveAt) && now.isBefore(departAt);
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
  late final List<ScheduledRun> _scheduled = [
    for (final run in runs) ?run.scheduled(observedAt),
  ]..sort((a, b) => a.arriveAt.compareTo(b.arriveAt));

  /// Includes the train currently dwelling; it drops out only when it departs.
  List<ScheduledRun> upcoming(DateTime now) {
    if (now.toUtc().difference(observedAt.toUtc()) >= const Duration(hours: 6)) return [];
    return _scheduled.where((run) => now.isBefore(run.departAt)).toList();
  }

  ArrivalDirection retainDwellingFrom(ArrivalDirection? previous, DateTime now) {
    final retained = previous?.upcoming(now).where((old) => old.isDwelling(now) &&
      !runs.any((fresh) => fresh.intimeStr == old.run.intimeStr)).toList() ?? [];
    if (retained.isEmpty) return this;
    return ArrivalDirection(lineId: lineId, flag: flag, stationId: stationId, observedAt: observedAt,
      runs: [...runs, for (final old in retained) old.run]);
  }
}

class ArrivalSnapshot {
  ArrivalSnapshot({required this.stationId, required List<ArrivalDirection> directions,
    required this.fetchedAt}) : directions = List.unmodifiable(directions);
  final int stationId;
  final List<ArrivalDirection> directions;
  final DateTime fetchedAt;

  /// Some refreshes list only approaching trains. Preserve a known platform stop until departure.
  ArrivalSnapshot retainDwellingFrom(ArrivalSnapshot? previous) {
    if (previous == null) return this;
    final merged = [
      for (final direction in directions) direction.retainDwellingFrom(
        previous.directions.where((old) => old.lineId == direction.lineId && old.flag == direction.flag).firstOrNull,
        fetchedAt),
      for (final old in previous.directions)
        if (!directions.any((fresh) => fresh.lineId == old.lineId && fresh.flag == old.flag))
          ArrivalDirection(lineId: old.lineId, flag: old.flag, stationId: stationId, observedAt: fetchedAt,
            runs: [for (final run in old.upcoming(fetchedAt)) if (run.isDwelling(fetchedAt)) run.run]),
    ];
    return ArrivalSnapshot(stationId: stationId, directions: merged, fetchedAt: fetchedAt);
  }
}
