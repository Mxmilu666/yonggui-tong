import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/arrival.dart';
import '../core/models/favorite_route.dart';
import '../core/models/station.dart';
import 'repositories/favorites_repository.dart';
import 'repositories/metro_repository.dart';

final preferencesProvider = Provider<SharedPreferences>((ref) =>
    throw StateError('启动时必须初始化本地存储'));
final metroRepositoryProvider = Provider<MetroRepository>((ref) {
  final repository = MetroRepository(preferences: ref.watch(preferencesProvider));
  ref.onDispose(repository.dispose);
  return repository;
});
final catalogProvider = AsyncNotifierProvider<CatalogController, StationCatalog>(CatalogController.new);
class CatalogController extends AsyncNotifier<StationCatalog> {
  @override
  Future<StationCatalog> build() {
    final repository = ref.watch(metroRepositoryProvider);
    final subscription = repository.catalogUpdates.listen((catalog) {
      state = AsyncData(catalog);
    }, onError: (Object error, StackTrace stack) {
      state = AsyncError<StationCatalog>(error, stack).copyWithPrevious(state);
    });
    ref.onDispose(subscription.cancel);
    return repository.loadCatalog();
  }
  Future<void> refresh({bool force = false}) async {
    state = const AsyncLoading<StationCatalog>().copyWithPrevious(state);
    try {
      state = AsyncData(await ref.read(metroRepositoryProvider).loadCatalog(force: force));
    } catch (error, stack) {
      state = AsyncError<StationCatalog>(error, stack).copyWithPrevious(state);
    }
  }
}

final favoritesProvider = NotifierProvider<FavoritesController, Set<int>>(FavoritesController.new);
class FavoritesController extends Notifier<Set<int>> {
  @override
  Set<int> build() => Set.unmodifiable(FavoritesRepository(ref.watch(preferencesProvider)).load());
  Future<void> toggle(int id) async {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    await FavoritesRepository(ref.read(preferencesProvider)).save(next);
    state = Set.unmodifiable(next);
  }
}

final favoriteRoutesProvider = NotifierProvider<FavoriteRoutesNotifier, List<FavoriteRoute>>(FavoriteRoutesNotifier.new);
class FavoriteRoutesNotifier extends Notifier<List<FavoriteRoute>> {
  @override
  List<FavoriteRoute> build() => FavoritesRepository(ref.watch(preferencesProvider)).loadRoutes();
  Future<void> toggle(FavoriteRoute route) async {
    final prefs = ref.read(preferencesProvider);
    await FavoritesRepository(prefs).toggleRoute(route);
    state = FavoritesRepository(prefs).loadRoutes();
  }

  bool contains(FavoriteRoute route) => state.contains(route);
}

class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.system, this.dynamicColor = false,
    this.refreshSeconds = 60, this.arrivalSeconds = false});
  final ThemeMode themeMode;
  final bool dynamicColor;
  final int refreshSeconds;
  final bool arrivalSeconds;
}
final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.watch(preferencesProvider);
    final mode = prefs.getString('settings.theme');
    return AppSettings(themeMode: ThemeMode.values.firstWhere((m) => m.name == mode,
      orElse: () => ThemeMode.system), dynamicColor: prefs.getBool('settings.dynamic') ?? false,
      refreshSeconds: prefs.getInt('settings.refresh') == 120 ? 120 : 60,
      arrivalSeconds: prefs.getBool('settings.arrivalSeconds') ?? false);
  }
  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(preferencesProvider).setString('settings.theme', mode.name);
    state = AppSettings(themeMode: mode, dynamicColor: state.dynamicColor,
      refreshSeconds: state.refreshSeconds, arrivalSeconds: state.arrivalSeconds);
  }
  Future<void> setDynamicColor(bool enabled) async {
    await ref.read(preferencesProvider).setBool('settings.dynamic', enabled);
    state = AppSettings(themeMode: state.themeMode, dynamicColor: enabled,
      refreshSeconds: state.refreshSeconds, arrivalSeconds: state.arrivalSeconds);
  }
  Future<void> setRefreshSeconds(int seconds) async {
    if (seconds != 60 && seconds != 120) throw ArgumentError.value(seconds);
    await ref.read(preferencesProvider).setInt('settings.refresh', seconds);
    state = AppSettings(themeMode: state.themeMode, dynamicColor: state.dynamicColor,
      refreshSeconds: seconds, arrivalSeconds: state.arrivalSeconds);
  }
  Future<void> setArrivalSeconds(bool enabled) async {
    await ref.read(preferencesProvider).setBool('settings.arrivalSeconds', enabled);
    state = AppSettings(themeMode: state.themeMode, dynamicColor: state.dynamicColor,
      refreshSeconds: state.refreshSeconds, arrivalSeconds: enabled);
  }
}

final lifecycleProvider = StateProvider<AppLifecycleState>((ref) => AppLifecycleState.resumed);
final nowProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now().toUtc();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now().toUtc());
});

class ArrivalState {
  const ArrivalState({this.snapshot, this.error, this.loading = false});
  final ArrivalSnapshot? snapshot;
  final String? error;
  final bool loading;
}
final arrivalsProvider = NotifierProvider.autoDispose.family<ArrivalsController, ArrivalState, int>(
    ArrivalsController.new);
class ArrivalsController extends AutoDisposeFamilyNotifier<ArrivalState, int> {
  Timer? _timer;
  bool _disposed = false;
  Future<void>? _refreshFlight;
  @override
  ArrivalState build(int arg) {
    final repository = ref.read(metroRepositoryProvider);
    ref.onDispose(() { _disposed = true; _timer?.cancel(); });
    ref.listen<AppLifecycleState>(lifecycleProvider, (previous, next) {
      _schedule();
      if (next == AppLifecycleState.resumed) unawaited(refresh());
    });
    ref.listen<int>(settingsProvider.select((s) => s.refreshSeconds), (_, next) => _schedule());
    _schedule();
    Future.microtask(() { if (!_disposed) unawaited(refresh()); });
    return ArrivalState(snapshot: repository.cachedArrival(arg));
  }
  void _schedule() {
    _timer?.cancel();
    if (ref.read(lifecycleProvider) != AppLifecycleState.resumed) return;
    _timer = Timer.periodic(Duration(seconds: ref.read(settingsProvider).refreshSeconds),
      (_) => unawaited(refresh()));
  }
  Future<void> refresh() {
    if (_disposed || ref.read(lifecycleProvider) != AppLifecycleState.resumed) return Future.value();
    if (_refreshFlight != null) return _refreshFlight!;
    state = ArrivalState(snapshot: state.snapshot, loading: true);
    final flight = () async {
      try {
        final snapshot = await ref.read(metroRepositoryProvider).arrivals(arg);
        if (!_disposed) state = ArrivalState(snapshot: snapshot);
      } catch (error) {
        if (!_disposed) state = ArrivalState(snapshot: state.snapshot, error: error.toString());
      }
    }();
    _refreshFlight = flight;
    unawaited(flight.then((_) { _refreshFlight = null; }));
    return flight;
  }
}
