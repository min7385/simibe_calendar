import 'package:flutter_test/flutter_test.dart';
import 'package:simibe_calendar/core/router/app_routes.dart';
import 'package:simibe_calendar/features/splash/splash_page.dart';

void main() {
  test('로그인되어 있지 않으면 로그인 화면으로 보낸다', () {
    expect(SplashPage.nextRouteAfterSplash(false), AppRoutes.login);
  });

  test('로그인되어 있으면 달력으로 보낸다', () {
    expect(SplashPage.nextRouteAfterSplash(true), AppRoutes.calendar);
  });
}
