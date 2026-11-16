class FavoriteRoute {
  FavoriteRoute({
    required this.originId,
    required this.destinationId,
    required this.name,
  });

  factory FavoriteRoute.fromJson(Map<String, dynamic> json) => FavoriteRoute(
    originId: json['origin'] as int,
    destinationId: json['destination'] as int,
    name: json['name'] as String,
  );

  final int originId;
  final int destinationId;
  final String name;

  Map<String, dynamic> toJson() => {
    'origin': originId,
    'destination': destinationId,
    'name': name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteRoute &&
          originId == other.originId &&
          destinationId == other.destinationId;

  @override
  int get hashCode => Object.hash(originId, destinationId);
}
