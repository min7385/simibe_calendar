import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const SimibeCalendarApp());
}

/// 앱 어디서나 쓰는 Supabase 클라이언트.
final supabase = Supabase.instance.client;

class SimibeCalendarApp extends StatelessWidget {
  const SimibeCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '심이베 캘린더',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF42A5F5)),
      home: const ConnectionCheckPage(),
    );
  }
}

/// Supabase 연결 확인용 임시 화면. 로그인 화면이 생기면 교체한다.
class ConnectionCheckPage extends StatefulWidget {
  const ConnectionCheckPage({super.key});

  @override
  State<ConnectionCheckPage> createState() => _ConnectionCheckPageState();
}

class _ConnectionCheckPageState extends State<ConnectionCheckPage> {
  String _message = '서버에 연결하는 중...';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final available = await supabase.rpc(
        'is_handle_available',
        params: {'p_handle': 'minsu2026'},
      );
      setState(() {
        _message = '연결 성공\n\n'
            '"minsu2026" 사용 가능 여부: $available\n'
            '(이미 가입한 아이디라 false가 정상)';
      });
    } catch (e) {
      setState(() => _message = '연결 실패\n\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('심이베 캘린더')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
