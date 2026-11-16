import 'package:flutter_test/flutter_test.dart';
import 'package:yonggui_tong/core/models/arrival.dart';

DateTime at(String clock, {int day = 16}) => DateTime.parse('2026-11-${day}T$clock+08:00');

ArrivalRun train(String arrival, String departure, {num inSeconds = 120, num outSeconds = 165, int sequence = 1}) =>
  ArrivalRun(sequence: sequence, intimeStr: arrival, outTimeStr: departure,
    intimeDura: inSeconds, outTimeDura: outSeconds);

ArrivalDirection direction(DateTime observed, List<ArrivalRun> runs, {int flag = 1}) =>
  ArrivalDirection(lineId: 1, flag: flag, stationId: 16, observedAt: observed, runs: runs);

ArrivalSnapshot snapshot(DateTime observed, List<ArrivalRun> runs) =>
  ArrivalSnapshot(stationId: 16, fetchedAt: observed, directions: [direction(observed, runs)]);

void main() {
  test('到站后保留当前列车，恰好离站才换下一班', () {
    final current = train('17:39:43', '17:40:28');
    final next = train('17:43:41', '17:44:26', sequence: 2);
    final board = direction(at('17:38:00'), [next, current]);
    expect(board.upcoming(at('17:39:42')).first.isDwelling(at('17:39:42')), isFalse);
    expect(board.upcoming(at('17:39:43')).first.isDwelling(at('17:39:43')), isTrue);
    expect(board.upcoming(at('17:40:27')).first.run, same(current));
    expect(board.upcoming(at('17:40:28')).first.run, same(next));
    expect(board.upcoming(at('17:44:26')), isEmpty);
  });

  test('首次查询时已进站仍能上车，不把负到站秒数当停运', () {
    for (final seconds in [0, -17]) {
      final observed = at(seconds == 0 ? '17:39:43' : '17:40:00');
      final board = direction(observed, [train('17:39:43', '17:40:28', inSeconds: seconds, outSeconds: 28)]);
      expect(board.upcoming(observed).single.isDwelling(observed), isTrue);
    }
    expect(direction(at('17:40:28'), [train('17:39:43', '17:40:28', inSeconds: -45, outSeconds: 0)])
      .upcoming(at('17:40:28')), isEmpty);
    expect(direction(at('02:00:00'), [train('02:00:51', '02:00:51', inSeconds: -60, outSeconds: -60)])
      .upcoming(at('02:00:00')), isEmpty);
  });

  test('跨午夜停靠和午夜后首次获取都锚定同一班次，不在翌日复活', () {
    final before = direction(at('23:59:00', day: 15), [train('23:59:50', '00:00:35')]);
    final after = direction(at('00:00:10'), [train('23:59:50', '00:00:35', inSeconds: -20, outSeconds: 25)]);
    for (final board in [before, after]) {
      final stop = board.upcoming(at('00:00:10')).single;
      expect(stop.arriveAt, at('23:59:50', day: 15));
      expect(stop.departAt, at('00:00:35'));
      expect(stop.isDwelling(at('00:00:10')), isTrue);
      expect(board.upcoming(at('00:00:35')), isEmpty);
      expect(board.upcoming(at('00:00:10', day: 17)), isEmpty);
    }
    final followingDay = direction(at('23:59:00', day: 15), [train('00:01:00', '00:01:45')]);
    expect(followingDay.upcoming(at('00:00:10')).single.arriveAt, at('00:01:00'));
    expect(direction(at('17:00:00'), [train('17:10:00', '17:09:00')]).upcoming(at('17:00:00')), isEmpty);
  });

  test('刷新漏掉停靠车时保留至离站，序号重排和新离站时间不产生重复车', () {
    final current = train('17:39:43', '17:40:28');
    final next = train('17:43:41', '17:44:26', sequence: 2);
    final previous = snapshot(at('17:38:00'), [current, next]);
    final fresh = snapshot(at('17:40:00'), [train('17:43:41', '17:44:26')]).retainDwellingFrom(previous);
    expect(fresh.directions.single.upcoming(at('17:40:00')).map((r) => r.run.intimeStr), ['17:39:43', '17:43:41']);
    expect(fresh.directions.single.upcoming(at('17:40:28')).map((r) => r.run.intimeStr), ['17:43:41']);
    final updated = snapshot(at('17:40:00'), [train('17:39:43', '17:40:40', inSeconds: -17, outSeconds: 40)])
      .retainDwellingFrom(previous);
    expect(updated.directions.single.upcoming(at('17:40:30')).single.departAt, at('17:40:40'));
    final removed = ArrivalSnapshot(stationId: 16, fetchedAt: at('17:40:00'), directions: []).retainDwellingFrom(previous);
    expect(removed.directions.single.upcoming(at('17:40:00')).single.run, same(current));
    final stale = snapshot(at('17:40:00', day: 17), []).retainDwellingFrom(previous);
    expect(stale.directions.single.upcoming(at('17:40:00', day: 17)), isEmpty);
  });
}
