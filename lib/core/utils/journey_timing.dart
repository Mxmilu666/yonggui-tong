import '../models/arrival.dart';
import '../models/route_plan.dart';
import '../models/station.dart';
import 'direction_resolver.dart';
import 'time_utils.dart';

/// Ride time per stop, the same weight the route estimate uses.
const rideTimePerStop = Duration(minutes: 2);

/// A transfer is flagged when the onward train leaves less than this after arrival.
const tightTransfer = Duration(minutes: 5);

/// A scheduled departure: the run and its absolute UTC departure (`OutTimeStr`).
typedef Departure = ({ArrivalRun run, DateTime at});

enum TransferStatus {
  /// Onward train found in the transfer station's schedule.
  connected,
  /// Estimated arrival is later than every published onward departure.
  beyondSchedule,
  /// The transfer station lists no onward run in the travel direction.
  noService,
  /// Schedule of the transfer station not loaded yet, or direction unknown.
  pending,
}

class TransferTiming {
  const TransferTiming({required this.stationId, required this.fromLine, required this.toLine,
    required this.toFlag, required this.arriveAt, required this.status, this.depart, this.lastKnown});

  final int stationId;
  final int fromLine;
  final int toLine;
  final int? toFlag;
  /// Estimated arrival: previous departure plus [rideTimePerStop] per stop.
  final DateTime arriveAt;
  final TransferStatus status;
  final Departure? depart;
  /// Latest published onward departure, when [status] is [TransferStatus.beyondSchedule].
  final DateTime? lastKnown;

  Duration? get gap => depart?.at.difference(arriveAt);
  bool get tight => gap != null && gap! < tightTransfer;
}

enum BoardStatus { boarded, noService, pending }

/// Timing of [RoutePlan] when boarding the next train at the origin right now.
class JourneyTiming {
  const JourneyTiming({required this.lineId, required this.flag, required this.status,
    this.board, this.transfers = const [], this.arriveAt});

  final int lineId;
  final int? flag;
  final BoardStatus status;
  final Departure? board;
  final List<TransferTiming> transfers;
  /// Estimated arrival at the destination; null when any transfer is unresolved.
  final DateTime? arriveAt;
}

/// Boards the next departure at the origin in the travel direction, rides
/// [rideTimePerStop] per stop, and at every transfer takes the first onward
/// departure listed by that station after the estimated arrival. Only real
/// `ScheduleTime` runs are used as departures; nothing is extrapolated.
JourneyTiming? journeyTiming({required RoutePlan plan, required Map<int, ArrivalSnapshot?> snapshots,
    required StationCatalog catalog, required DateTime now}) {
  if (plan.segments.isEmpty) return null;
  List<Departure> departures(ArrivalSnapshot snapshot, int line, int flag) {
    final result = <Departure>[
      for (final direction in snapshot.directions)
        if (direction.lineId == line && direction.flag == flag)
          for (final run in direction.validRuns(now))
            if (TimeUtils.remaining(run.outTimeStr, now, intimeDura: run.intimeDura) case final left?)
              (run: run, at: now.add(left)),
    ];
    result.sort((a, b) => a.at.compareTo(b.at));
    return result;
  }

  final first = plan.segments.first;
  final flag = DirectionResolver.flagToward(lineId: first.lineId,
    fromId: first.stationIds.first, toId: first.stationIds.last, catalog: catalog);
  final origin = snapshots[plan.originId];
  if (flag == null || origin == null) {
    return JourneyTiming(lineId: first.lineId, flag: flag, status: BoardStatus.pending);
  }
  final boardOptions = departures(origin, first.lineId, flag);
  if (boardOptions.isEmpty) {
    return JourneyTiming(lineId: first.lineId, flag: flag, status: BoardStatus.noService);
  }
  final board = boardOptions.first;
  final transfers = <TransferTiming>[];
  DateTime? cursor = board.at;
  for (var index = 0; index < plan.segments.length - 1; index++) {
    final segment = plan.segments[index];
    final onward = plan.segments[index + 1];
    final stationId = segment.stationIds.last;
    final arriveAt = cursor!.add(rideTimePerStop * segment.stops);
    final toFlag = DirectionResolver.flagToward(lineId: onward.lineId,
      fromId: stationId, toId: onward.stationIds.last, catalog: catalog);
    final snapshot = snapshots[stationId];
    TransferTiming transfer(TransferStatus status, {Departure? depart, DateTime? lastKnown}) => TransferTiming(
      stationId: stationId, fromLine: segment.lineId, toLine: onward.lineId, toFlag: toFlag,
      arriveAt: arriveAt, status: status, depart: depart, lastKnown: lastKnown);
    if (toFlag == null || snapshot == null) {
      transfers.add(transfer(TransferStatus.pending));
      cursor = null;
      break;
    }
    final options = departures(snapshot, onward.lineId, toFlag);
    final depart = options.where((option) => option.at.isAfter(arriveAt)).firstOrNull;
    if (depart == null) {
      transfers.add(options.isEmpty ? transfer(TransferStatus.noService)
        : transfer(TransferStatus.beyondSchedule, lastKnown: options.last.at));
      cursor = null;
      break;
    }
    transfers.add(transfer(TransferStatus.connected, depart: depart));
    cursor = depart.at;
  }
  return JourneyTiming(lineId: first.lineId, flag: flag, status: BoardStatus.boarded, board: board,
    transfers: transfers, arriveAt: cursor?.add(rideTimePerStop * plan.segments.last.stops));
}
