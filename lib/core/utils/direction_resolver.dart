import '../models/station.dart';

abstract final class DirectionResolver {
  // LineId + Flag -> terminal Code, verified on 2026-11-16 against
  // StationTimes in https://metroinfo.ditiego.net/Api/Stations/{16,88,134,170}.
  // Reference data only: no extra runtime API, no hard-coded ScheduleTime IDs.
  static const _terminalCodes = <(int, int), String>{
    (1, 1): '0129', (1, 2): '0101',
    (2, 1): '0257', (2, 2): '0231',
    (3, 1): '0345', (3, 2): '3151',
    (4, 1): '0456', (4, 2): '0430',
    (5, 1): '0557', (5, 2): '0531',
    (6, 1): '0654', (6, 2): '0632',
    (7, 1): '0755', (7, 2): '0731',
    (8, 1): '0849', (8, 2): '0832',
    (12, 1): '1231', (12, 2): '1240',
  };

  static String label({required int lineId, required int flag, required StationCatalog? catalog}) {
    final code = _terminalCodes[(lineId, flag)];
    final id = code == null ? null : catalog?.dictionary[code];
    final station = id == null ? null : catalog?.stationById(id);
    if (station == null || !station.codes.contains(code) || !station.lineIds.contains(lineId)) {
      return '方向 $flag（终点待确认）';
    }
    return '往 ${station.name}';
  }
}
