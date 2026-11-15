import 'package:shared_preferences/shared_preferences.dart';

class FavoritesRepository {
  FavoritesRepository(this.preferences);
  final SharedPreferences preferences;
  static const storageKey = 'metro.favorites.v1';
  Set<int> load() => (preferences.getStringList(storageKey) ?? [])
      .map(int.tryParse).whereType<int>().where((id) => id > 0).toSet();
  Future<void> save(Set<int> ids) async {
    await preferences.setStringList(storageKey, ids.map((id) => '$id').toList());
  }
}
