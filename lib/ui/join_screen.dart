import 'package:flutter/material.dart';

import '../config/janus_config.dart';
import 'echo_test_screen.dart';
import 'room_screen.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';

/// 서버 주소와 방 정보를 입력받아 [RoomScreen] 으로 넘긴다.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrl = TextEditingController(text: JanusConfig.defaultServerUrl);
  final _room = TextEditingController(text: JanusConfig.defaultRoom);
  final _displayName = TextEditingController();
  final _pin = TextEditingController();
  final _apiSecret =
      TextEditingController(text: JanusConfig.defaultApiSecret);

  @override
  void dispose() {
    _serverUrl.dispose();
    _room.dispose();
    _displayName.dispose();
    _pin.dispose();
    _apiSecret.dispose();
    super.dispose();
  }

  void _join() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoomScreen(
          serverUrl: _serverUrl.text.trim(),
          room: _room.text.trim(),
          displayName: _displayName.text.trim(),
          pin: _pin.text.trim(),
          apiSecret: _apiSecret.text.trim(),
        ),
      ),
    );
  }

  /// EchoTest 는 방/이름이 필요 없으므로 서버 주소만 확인하고 바로 넘어간다.
  void _startEchoTest() {
    final url = _serverUrl.text.trim();
    if (!JanusConfig.isSupportedUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서버 주소를 먼저 올바르게 입력하세요')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EchoTestScreen(
          serverUrl: url,
          apiSecret: _apiSecret.text.trim(),
        ),
      ),
    );
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label을(를) 입력하세요';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Janus VideoRoom')),
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionLabel('시그널링 서버',
                            icon: Icons.dns_outlined),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _serverUrl,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Janus 시그널링 주소',
                            helperText:
                                'ws:// wss:// 는 WebSocket, http:// https:// 는 REST',
                            prefixIcon: Icon(Icons.link, size: 20),
                          ),
                          validator: (v) {
                            final base = _required(v, '서버 주소');
                            if (base != null) return base;
                            if (!JanusConfig.isSupportedUrl(v!.trim())) {
                              return 'ws:// wss:// http:// https:// 중 하나여야 합니다';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _apiSecret,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'API Secret (선택)',
                            helperText:
                                'janus.jcfg 에 api_secret 이 설정된 서버라면 필수입니다',
                            prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionLabel('방 정보',
                            icon: Icons.meeting_room_outlined),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _room,
                          decoration: const InputDecoration(
                            labelText: '방 번호',
                            prefixIcon: Icon(Icons.numbers, size: 20),
                          ),
                          validator: (v) => _required(v, '방 번호'),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _displayName,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: '표시 이름',
                            prefixIcon: Icon(Icons.person_outline, size: 20),
                          ),
                          validator: (v) => _required(v, '표시 이름'),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _pin,
                          decoration: const InputDecoration(
                            labelText: 'PIN (선택)',
                            helperText: '방에 PIN 이 걸려 있을 때만 입력합니다',
                            prefixIcon: Icon(Icons.lock_outline, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  GlowButton(
                    label: '방 참가',
                    icon: Icons.videocam,
                    onPressed: _join,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _startEchoTest,
                    icon: const Icon(Icons.graphic_eq, size: 18),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('EchoTest 로 연결 확인'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '방이나 다른 참가자 없이 서버 연결·인증서·카메라 권한을 검증합니다',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
