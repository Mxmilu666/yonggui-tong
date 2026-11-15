class RouteSegment {
  RouteSegment({required this.lineId, required List<int> stationIds})
      : stationIds = List.unmodifiable(stationIds);
  final int lineId;
  final List<int> stationIds;
  int get stops => stationIds.length - 1;
}

class RoutePlan {
  RoutePlan({required this.originId, required this.destinationId,
    required List<RouteSegment> segments, required this.minutes})
      : segments = List.unmodifiable(segments);
  final int originId;
  final int destinationId;
  final List<RouteSegment> segments;
  final int minutes;
  int get transfers => segments.isEmpty ? 0 : segments.length - 1;
  int get stops => segments.fold(0, (total, segment) => total + segment.stops);
}
