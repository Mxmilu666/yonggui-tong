import '../models/arrival.dart';
import '../models/route_plan.dart';
import '../models/station.dart';
import 'direction_resolver.dart';
import 'time_utils.dart';

/// Timetable connection at one transfer station of a [RoutePlan].
class TransferConnection {
  const TransferConnection({required this.stationId, required this.fromLine, required this.toLine,
    required this.arrive, required this.depart, required this.gap});

  final int stationId;
  final int fromLine;
  final int toLine;
  /// Next incoming train in the travel direction (use `intimeStr`).
  final ArrivalRun arrive;
  /// First onward train in the travel direction leaving after [arrive] (use `outTimeStr`).
  final ArrivalRun depart;
  final Duration gap;

  bool get tight => gap < const Duration(minutes: 5);
}

/// Connection between `plan.segments[index]` and `plan.segments[index + 1]`, from the
/// transfer station's own schedule. Null when a direction or a matching train is unknown.
TransferConnection? transferConnection({required RoutePlan plan, required int index,
    required ArrivalSnapshot snapshot, required StationCatalog catalog, required DateTime now}) {
  final incoming = plan.segments[index];
  final outgoing = plan.segments[index + 1];
  final stationId = incoming.stationIds.last;
  final inFlag = DirectionResolver.flagToward(lineId: incoming.lineId,
    fromId: incoming.stationIds.first, toId: stationId, catalog: catalog);
  final outFlag = DirectionResolver.flagToward(lineId: outgoing.lineId,
    fromId: stationId, toId: outgoing.stationIds.last, catalog: catalog);
  if (inFlag == null || outFlag == null) return null;
  List<ArrivalRun> runs(int line, int flag) => [
    for (final direction in snapshot.directions)
      if (direction.lineId == line && direction.flag == flag) ...direction.upcoming(now),
  ];
  final arrivals = runs(incoming.lineId, inFlag);
  if (arrivals.isEmpty) return null;
  final arrive = arrivals.first;
  final arriveIn = TimeUtils.remaining(arrive.intimeStr, now, intimeDura: arrive.intimeDura)!;
  for (final depart in runs(outgoing.lineId, outFlag)) {
    final departIn = TimeUtils.remaining(depart.outTimeStr, now, intimeDura: depart.intimeDura);
    if (departIn != null && departIn > arriveIn) {
      return TransferConnection(stationId: stationId, fromLine: incoming.lineId, toLine: outgoing.lineId,
        arrive: arrive, depart: depart, gap: departIn - arriveIn);
    }
  }
  return null;
}
