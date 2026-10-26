import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/login_page.dart';
import '../../features/calendar/calendar_page.dart';
import '../../features/splash/splash_page.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(Supabase.instance.client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      final atSplash = state.matchedLocation == AppRoutes.splash;
      final atLogin = state.matchedLocation == AppRoutes.login;

      if (atSplash) return null;
      if (!loggedIn && !atLogin) return AppRoutes.login;
      if (loggedIn && atLogin) return AppRoutes.calendar;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (context, state) => const CalendarPage(),
      ),
    ],
  );
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
