import '../models/arrival.dart';
import '../models/route_plan.dart';
import '../models/station.dart';
import 'direction_resolver.dart';
import 'journey_timing.dart';
import 'time_utils.dart';

/// One state of a live trip; shown from [at] until the next stage. [countdownTo] drives the
/// status-bar chip timer.
class LiveStage {
  const LiveStage({required this.at, required this.title, required this.text, this.countdownTo});

  final DateTime at;
  final String title;
  final String text;
  final DateTime? countdownTo;

  Map<String, Object?> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'text': text,
    'countdownTo': countdownTo?.millisecondsSinceEpoch,
  };
}

/// Everything the native Live Update needs: it switches stages on its own and ends at [endsAt].
class LiveTripPlan {
  const LiveTripPlan({required this.stages, required this.endsAt, required this.open});

  final List<LiveStage> stages;
  final DateTime endsAt;
  /// go_router path opened when the notification is tapped.
  final String open;

  Map<String, Object?> toJson() => {
    'stages': [for (final stage in stages) stage.toJson()],
    'endsAt': endsAt.millisecondsSinceEpoch,
    'open': open,
  };
}

String _clock(DateTime at) => TimeUtils.formatBeijing(at);
String _about(DateTime at) => '约 ${TimeUtils.formatBeijing(at, pattern: 'HH:mm')}';
String _slot(Slot slot) => slot.projected ? _about(slot.at) : _clock(slot.at);

/// Count down to one scheduled train, then say it is arriving and end two minutes later.
LiveTripPlan waitForTrain({required Station station, required int lineId, required String direction,
    required ArrivalRun run, required DateTime arriveAt, required DateTime now}) {
  final title = '${station.name} · $lineId号线 $direction';
  return LiveTripPlan(
    open: '/arrivals/${station.id}',
    endsAt: arriveAt.add(const Duration(minutes: 2)),
    stages: [
      LiveStage(at: now, title: title, text: '${run.intimeStr} 到站 · 第${run.sequence}班 · 按时刻表',
        countdownTo: arriveAt),
      LiveStage(at: arriveAt, title: title, text: '列车进站 · 按时刻表'),
    ],
  );
}

/// Leave now: wait for the train, ride each leg, say whether each transfer needs a hurry, arrive.
/// Null when the origin has no departure to board.
LiveTripPlan? journeyTrip({required RoutePlan plan, required JourneyTiming timing,
    required StationCatalog catalog, required DateTime now}) {
  final board = timing.board;
  if (timing.status != BoardStatus.boarded || board == null) return null;
  String name(int id) => catalog.stationById(id)!.name;
  String leg(int index) {
    final segment = plan.segments[index];
    final flag = DirectionResolver.flagToward(lineId: segment.lineId,
      fromId: segment.stationIds.first, toId: segment.stationIds.last, catalog: catalog);
    return flag == null ? '${segment.lineId}号线'
      : '${segment.lineId}号线 ${DirectionResolver.label(lineId: segment.lineId, flag: flag, catalog: catalog)}';
  }

  final destination = name(plan.destinationId);
  final stages = <LiveStage>[
    LiveStage(at: now, title: '${name(plan.originId)} → $destination',
      text: '${leg(0)} ${_clock(board)} 开 · 准备上车', countdownTo: board),
  ];
  var cursor = board;
  for (var index = 0; index < plan.segments.length; index++) {
    if (index == plan.segments.length - 1) {
      final arrival = timing.arriveAt!;
      stages.add(LiveStage(at: cursor, title: '乘坐 ${leg(index)}',
        text: '${_about(arrival)} 到达$destination', countdownTo: arrival));
      return LiveTripPlan(stages: stages, endsAt: arrival.add(const Duration(minutes: 2)),
        open: '/planner?from=${plan.originId}&to=${plan.destinationId}');
    }
    final transfer = timing.transfers[index];
    final station = name(transfer.stationId);
    final depart = transfer.depart;
    final hurry = transfer.hurry;
    if (transfer.status != TransferStatus.connected || depart == null || hurry == null) {
      stages
        ..add(LiveStage(at: cursor, title: '乘坐 ${leg(index)}',
          text: '${_about(transfer.arriveAt)} 到$station，换乘 ${leg(index + 1)}', countdownTo: transfer.arriveAt))
        ..add(LiveStage(at: transfer.arriveAt, title: '$station换乘',
          text: '${leg(index + 1)} 的班次暂时推算不出，请以站台显示为准'));
      return LiveTripPlan(stages: stages, endsAt: transfer.arriveAt.add(const Duration(minutes: 30)),
        open: '/planner?from=${plan.originId}&to=${plan.destinationId}');
    }
    final next = transfer.nextDepart;
    stages
      ..add(LiveStage(at: cursor, title: '乘坐 ${leg(index)}',
        text: '${_about(transfer.arriveAt)} 到$station，换乘 ${leg(index + 1)} ${_slot(depart)} 开 · ${hurry.label}',
        countdownTo: transfer.arriveAt))
      ..add(LiveStage(at: transfer.arriveAt, title: '$station换乘 · ${hurry.label}',
        text: '${leg(index + 1)} ${_slot(depart)} 开'
          '${hurry == Hurry.risky && next != null ? '，错过则下一班 ${_slot(next)}' : ''}',
        countdownTo: depart.at));
    cursor = depart.at;
  }
  return null;
}
