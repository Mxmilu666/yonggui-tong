import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../core/models/favorite_route.dart';

class FavoritesRepository {
  FavoritesRepository(this.preferences);
  final SharedPreferences preferences;
  static const storageKey = 'metro.favorites.v1';
  static const routesStorageKey = 'metro.favorite_routes.v1';

  Set<int> load() => (preferences.getStringList(storageKey) ?? [])
      .map(int.tryParse).whereType<int>().where((id) => id > 0).toSet();
  Future<void> save(Set<int> ids) async {
    await preferences.setStringList(storageKey, ids.map((id) => '$id').toList());
  }

  List<FavoriteRoute> loadRoutes() {
    final json = preferences.getStringList(routesStorageKey) ?? [];
    return json.map((str) {
      try {
        return FavoriteRoute.fromJson(jsonDecode(str) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<FavoriteRoute>().toList();
  }

  Future<void> saveRoutes(List<FavoriteRoute> routes) async {
    await preferences.setStringList(
      routesStorageKey,
      routes.map((route) => jsonEncode(route.toJson())).toList(),
    );
  }

  Future<void> toggleRoute(FavoriteRoute route) async {
    final routes = loadRoutes();
    if (routes.contains(route)) {
      routes.remove(route);
    } else {
      routes.add(route);
    }
    await saveRoutes(routes);
  }
}
