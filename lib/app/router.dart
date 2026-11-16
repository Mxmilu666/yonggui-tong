import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../features/arrivals/arrivals_page.dart';
import '../features/home/home_page.dart';
import '../features/lines/lines_page.dart';
import '../features/map/map_page.dart';
import '../features/planner/planner_page.dart';
import '../features/settings/settings_page.dart';
import '../features/stations/station_page.dart';

/// MD3 fade-through for top-level destinations: the old page fades out in the first
/// 35 %, then the new one fades in while scaling up from 92 %.
CustomTransitionPage<void> _fadeThrough(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 300),
  reverseTransitionDuration: const Duration(milliseconds: 300),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final enter = CurvedAnimation(parent: animation, curve: const Interval(.35, 1, curve: Curves.easeOutCubic));
    final exit = CurvedAnimation(parent: secondaryAnimation, curve: const Interval(0, .35, curve: Curves.easeInCubic));
    return FadeTransition(
      opacity: ReverseAnimation(exit),
      child: FadeTransition(
        opacity: enter,
        child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(enter), child: child),
      ),
    );
  },
);

final appRouter = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => _NavigationShell(
        location: state.uri.path,
        child: child,
      ),
      routes: [
        GoRoute(path: '/', pageBuilder: (_, state) => _fadeThrough(state, const HomePage())),
        GoRoute(path: '/arrivals', pageBuilder: (_, state) => _fadeThrough(state, const ArrivalsPage())),
        GoRoute(path: '/arrivals/:id', pageBuilder: (_, state) => _fadeThrough(state, ArrivalsPage(
          stationId: int.tryParse(state.pathParameters['id'] ?? ''),
        ))),
        GoRoute(path: '/map', pageBuilder: (_, state) => _fadeThrough(state, const MapPage())),
        GoRoute(path: '/settings', pageBuilder: (_, state) => _fadeThrough(state, const SettingsPage())),
      ],
    ),
    GoRoute(path: '/lines', builder: (_, _) => const LinesPage()),
    GoRoute(path: '/lines/:id', builder: (_, state) => LinesPage(
      lineId: int.tryParse(state.pathParameters['id'] ?? ''),
    )),
    GoRoute(path: '/stations/:id', builder: (_, state) => StationPage(
      stationId: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
    )),
    GoRoute(path: '/planner', builder: (_, state) => PlannerPage(
      originId: int.tryParse(state.uri.queryParameters['from'] ?? ''),
      destinationId: int.tryParse(state.uri.queryParameters['to'] ?? ''),
    )),
    GoRoute(path: '/about', builder: (_, _) => const AboutPage()),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('页面未找到')),
    body: Center(child: FilledButton(
      onPressed: () => context.go('/'), child: const Text('返回首页'),
    )),
  ),
);

class _NavigationShell extends StatelessWidget {
  const _NavigationShell({required this.location, required this.child});
  final String location;
  final Widget child;

  static const _destinations = [
    (path: '/', label: '首页', icon: Icons.home_outlined, selected: Icons.home_rounded),
    (path: '/arrivals', label: '到站', icon: Icons.schedule_outlined, selected: Icons.schedule),
    (path: '/map', label: '线网', icon: Icons.hub_outlined, selected: Icons.hub),
    (path: '/settings', label: '我的', icon: Icons.person_outline, selected: Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final index = location.startsWith('/arrivals') ? 1
      : location.startsWith('/map') ? 2
      : location.startsWith('/settings') ? 3 : 0;
    void select(int selected) => context.go(_destinations[selected].path);
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 840) {
        return Scaffold(body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: select,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Icon(Icons.train_rounded, size: 32, semanticLabel: '甬轨通'),
            ),
            destinations: [for (final item in _destinations)
              NavigationRailDestination(
                icon: Icon(item.icon), selectedIcon: Icon(item.selected),
                label: Text(item.label),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ]));
      }
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: select,
          destinations: [for (final item in _destinations)
            NavigationDestination(icon: Icon(item.icon),
              selectedIcon: Icon(item.selected), label: item.label),
          ],
        ),
      );
    });
  }
}
