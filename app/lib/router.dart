import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'state/providers.dart';
import 'ui/screens/activity_screen.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/insights_screen.dart';
import 'ui/screens/plan_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever the session changes.
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  NoTransitionPage<void> page(Widget child) => NoTransitionPage(child: child);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      final onAuth = loc == '/signin' || loc == '/signup';
      return switch (session) {
        SessionLoading() => loc == '/loading' ? null : '/loading',
        SignedOut() => onAuth ? null : '/signin',
        SignedIn(needsSetup: true) => loc == '/setup' ? null : '/setup',
        SignedIn() =>
          (onAuth || loc == '/setup' || loc == '/loading') ? '/home' : null,
      };
    },
    routes: [
      GoRoute(
        path: '/loading',
        pageBuilder: (_, _) => page(
          const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
      ),
      GoRoute(
        path: '/signin',
        pageBuilder: (_, _) => page(const AuthScreen(signUp: false)),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (_, _) => page(const AuthScreen(signUp: true)),
      ),
      GoRoute(path: '/setup', pageBuilder: (_, _) => page(const SetupScreen())),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, _) => page(const HomeScreen()),
          ),
          GoRoute(
            path: '/activity',
            pageBuilder: (_, _) => page(const ActivityScreen()),
          ),
          GoRoute(
            path: '/insights',
            pageBuilder: (_, _) => page(const InsightsScreen()),
          ),
          GoRoute(
            path: '/plan',
            pageBuilder: (_, _) => page(const PlanScreen()),
          ),
        ],
      ),
    ],
  );
});
