import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config/tls_bootstrap.dart';
import 'ui/theme/app_theme.dart';
import 'ui/connect_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 사설 CA 신뢰 설정은 첫 WebSocket 연결보다 반드시 먼저 끝나야 한다.
  await configureJanusTls();
  // 착신은 60초 안에 등록까지 끝내야 한다. 통화 시작 시점에 권한을 물으면
  // 그 사이에 시간을 까먹으므로 첫 실행 때 미리 받아 둔다.
  await _ensureCallPermissions();
  runApp(const JanusClientApp());
}

Future<void> _ensureCallPermissions() async {
  try {
    await Permission.microphone.request();
  } catch (e) {
    debugPrint('마이크 권한 요청 실패: $e');
  }
}

class JanusClientApp extends StatelessWidget {
  const JanusClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Janus SIP Client',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const ConnectScreen(),
    );
  }
}
