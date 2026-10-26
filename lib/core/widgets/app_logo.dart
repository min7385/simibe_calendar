import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 시작 화면과 인증 화면에서 쓰는 임시 로고. 나중에 이미지로 바꿀 수 있다.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.showName = true, this.size = 88});

  final bool showName;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.personal,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.calendar_month_rounded, size: size * 0.52, color: AppColors.white),
        ),
        if (showName) ...[
          const SizedBox(height: 20),
          Text(
            '심이베 캘린더',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ],
    );
  }
}
