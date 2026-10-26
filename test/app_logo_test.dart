import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simibe_calendar/core/widgets/app_logo.dart';

void main() {
  testWidgets('앱 로고와 이름을 보여 준다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppLogo())));

    expect(find.text('심이베 캘린더'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
  });
}
