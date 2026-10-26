import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_logo.dart';

/// SCR-002 로그인. 다음 단계에서 입력란과 로그인 기능을 넣는다.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(),
              const SizedBox(height: 32),
              Text(
                '로그인 화면은 다음 단계에서 만들어요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.sub, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
