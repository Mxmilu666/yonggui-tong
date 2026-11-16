import '../models/arrival.dart';
import '../models/route_plan.dart';
import '../models/station.dart';
import 'direction_resolver.dart';
import 'time_utils.dart';

/// Ride time per stop, the same weight the route estimate uses.
const rideTimePerStop = Duration(minutes: 2);

/// An estimated arrival snaps to a train in the transfer station's schedule within this window.
const _snapWindow = Duration(minutes: 3);

/// Headways outside this range are not used to project later trains.
const _minHeadway = Duration(seconds: 90);
const _maxHeadway = Duration(minutes: 20);

/// One train time at a station: published by `ScheduleTime`, or projected from its headway.
typedef Slot = ({DateTime at, bool projected});

enum TransferStatus {
  /// An onward train was found (published or projected).
  connected,
  /// No onward train can be determined: the last published one leaves before arrival and
  /// no headway is available to project further.
  beyondSchedule,
  /// The transfer station lists no onward run in the travel direction.
  noService,
  /// Schedule of the transfer station not loaded yet, or direction unknown.
  pending,
}

/// How much slack a connection leaves.
enum Hurry {
  /// At least 5 minutes between arrival and the onward departure.
  relaxed,
  /// 2 to 5 minutes.
  hurry,
  /// Under 2 minutes.
  risky,
}

class TransferTiming {
  const TransferTiming({required this.stationId, required this.fromLine, required this.toLine,
    required this.toFlag, required this.arriveAt, required this.status, this.depart, this.nextDepart,
    this.lastKnown});

  final int stationId;
  final int fromLine;
  final int toLine;
  final int? toFlag;
  /// Estimated arrival, aligned to the transfer station's own arrival times when one is close.
  final DateTime arriveAt;
  final TransferStatus status;
  /// First onward train leaving after [arriveAt].
  final Slot? depart;
  /// The onward train after [depart], for when [depart] is missed.
  final Slot? nextDepart;
  /// Latest published onward departure, when [status] is [TransferStatus.beyondSchedule].
  final DateTime? lastKnown;

  Duration? get gap => depart?.at.difference(arriveAt);

  Hurry? get hurry {
    final slack = gap;
    if (slack == null) return null;
    if (slack < const Duration(minutes: 2)) return Hurry.risky;
    if (slack < const Duration(minutes: 5)) return Hurry.hurry;
    return Hurry.relaxed;
  }
}

enum BoardStatus { boarded, noService, pending }

/// Timing of [RoutePlan] when boarding the next train at the origin right now.
class JourneyTiming {
  const JourneyTiming({required this.lineId, required this.flag, required this.status,
    this.board, this.transfers = const [], this.arriveAt});

  final int lineId;
  final int? flag;
  final BoardStatus status;
  /// Next published departure (`OutTimeStr`) at the origin.
  final DateTime? board;
  final List<TransferTiming> transfers;
  /// Estimated arrival at the destination; null when any transfer is unresolved.
  final DateTime? arriveAt;

  /// The tightest connection on the route.
  Hurry? get hurry {
    Hurry? worst;
    for (final transfer in transfers) {
      final hurry = transfer.hurry;
      if (hurry != null && (worst == null || hurry.index > worst.index)) worst = hurry;
    }
    return worst;
  }
}

/// Boards the next departure at the origin in the travel direction and rides
/// [rideTimePerStop] per stop. At each transfer the estimate is aligned to the
/// nearest incoming train listed by that station, then the first onward train
/// after it is taken. `ScheduleTime` lists about two trains per direction; later
/// trains are projected by repeating the gap between the last two listed ones.
JourneyTiming? journeyTiming({required RoutePlan plan, required Map<int, ArrivalSnapshot?> snapshots,
    required StationCatalog catalog, required DateTime now}) {
  if (plan.segments.isEmpty) return null;
  List<DateTime> published(ArrivalSnapshot snapshot, int line, int flag, {required bool departures}) {
    final times = <DateTime>[
      for (final direction in snapshot.directions)
        if (direction.lineId == line && direction.flag == flag)
          for (final run in direction.validRuns(now))
            if (TimeUtils.remaining(departures ? run.outTimeStr : run.intimeStr, now,
                intimeDura: run.intimeDura) case final left?)
              now.add(left),
    ]..sort();
    return times;
  }

  final first = plan.segments.first;
  final flag = DirectionResolver.flagToward(lineId: first.lineId,
    fromId: first.stationIds.first, toId: first.stationIds.last, catalog: catalog);
  final origin = snapshots[plan.originId];
  if (flag == null || origin == null) {
    return JourneyTiming(lineId: first.lineId, flag: flag, status: BoardStatus.pending);
  }
  final boardOptions = published(origin, first.lineId, flag, departures: true);
  if (boardOptions.isEmpty) {
    return JourneyTiming(lineId: first.lineId, flag: flag, status: BoardStatus.noService);
  }
  final board = boardOptions.first;
  final transfers = <TransferTiming>[];
  DateTime? cursor = board;
  for (var index = 0; index < plan.segments.length - 1; index++) {
    final segment = plan.segments[index];
    final onward = plan.segments[index + 1];
    final stationId = segment.stationIds.last;
    final estimate = cursor!.add(rideTimePerStop * segment.stops);
    final inFlag = DirectionResolver.flagToward(lineId: segment.lineId,
      fromId: segment.stationIds.first, toId: stationId, catalog: catalog);
    final toFlag = DirectionResolver.flagToward(lineId: onward.lineId,
      fromId: stationId, toId: onward.stationIds.last, catalog: catalog);
    final snapshot = snapshots[stationId];
    if (inFlag == null || toFlag == null || snapshot == null) {
      transfers.add(TransferTiming(stationId: stationId, fromLine: segment.lineId, toLine: onward.lineId,
        toFlag: toFlag, arriveAt: estimate, status: TransferStatus.pending));
      cursor = null;
      break;
    }
    final horizon = estimate.add(const Duration(minutes: 40));
    // The user's own train is the listed (or projected) arrival nearest to the ride estimate.
    DateTime? nearest;
    for (final slot in _slots(published(snapshot, segment.lineId, inFlag, departures: false), horizon)) {
      if (!slot.at.isAfter(cursor)) continue;
      if (nearest == null || slot.at.difference(estimate).abs() < nearest.difference(estimate).abs()) {
        nearest = slot.at;
      }
    }
    final arriveAt = nearest != null && nearest.difference(estimate).abs() <= _snapWindow ? nearest : estimate;
    final outPublished = published(snapshot, onward.lineId, toFlag, departures: true);
    final onwardSlots = _slots(outPublished, horizon).where((slot) => slot.at.isAfter(arriveAt)).take(2).toList();
    TransferTiming transfer(TransferStatus status, {DateTime? lastKnown}) => TransferTiming(
      stationId: stationId, fromLine: segment.lineId, toLine: onward.lineId, toFlag: toFlag,
      arriveAt: arriveAt, status: status, lastKnown: lastKnown,
      depart: onwardSlots.firstOrNull, nextDepart: onwardSlots.length > 1 ? onwardSlots[1] : null);
    if (onwardSlots.isEmpty) {
      transfers.add(outPublished.isEmpty ? transfer(TransferStatus.noService)
        : transfer(TransferStatus.beyondSchedule, lastKnown: outPublished.last));
      cursor = null;
      break;
    }
    transfers.add(transfer(TransferStatus.connected));
    cursor = onwardSlots.first.at;
  }
  return JourneyTiming(lineId: first.lineId, flag: flag, status: BoardStatus.boarded, board: board,
    transfers: transfers, arriveAt: cursor?.add(rideTimePerStop * plan.segments.last.stops));
}

/// Published times, then the last listed headway repeated up to [until].
Iterable<Slot> _slots(List<DateTime> published, DateTime until) sync* {
  for (final at in published) {
    yield (at: at, projected: false);
  }
  if (published.length < 2) return;
  final headway = published.last.difference(published[published.length - 2]);
  if (headway < _minHeadway || headway > _maxHeadway) return;
  for (var at = published.last.add(headway); !at.isAfter(until); at = at.add(headway)) {
    yield (at: at, projected: true);
  }
}
