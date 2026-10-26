import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_routes.dart';
import '../../core/widgets/app_logo.dart';

/// SCR-001 시작. 로고를 보여 준 뒤 로그인 여부로 다음 화면을 고른다.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  /// 로그인되어 있으면 달력, 아니면 로그인 화면 (REQ-AUTH-005).
  static String nextRouteAfterSplash(bool loggedIn) {
    return loggedIn ? AppRoutes.calendar : AppRoutes.login;
  }

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const _minVisible = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    _goNext();
  }

  Future<void> _goNext() async {
    await Future<void>.delayed(_minVisible);
    if (!mounted) return;

    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    context.go(SplashPage.nextRouteAfterSplash(loggedIn));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: AppLogo()),
    );
  }
}
