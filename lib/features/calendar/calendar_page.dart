import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// SCR-010 달력. 다음 단계에서 월간 달력을 넣는다.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('달력')),
      body: const Center(
        child: Text(
          '달력 화면은 로그인 이후에 만들어요.',
          style: TextStyle(color: AppColors.sub, fontSize: 15),
        ),
      ),
    );
  }
}
