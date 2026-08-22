import 'package:flutter/material.dart';

import '../config/janus_config.dart';
import '../services/sip_service.dart';
import 'dialer_screen.dart';
import 'echo_test_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';
import 'widgets/janus_mark.dart';

/// 서버 접속 정보와 SIP 계정을 받아 등록까지 진행한다.
class SipLoginScreen extends StatefulWidget {
  const SipLoginScreen({super.key});

  @override
  State<SipLoginScreen> createState() => _SipLoginScreenState();
}

class _SipLoginScreenState extends State<SipLoginScreen> {
  final SipService _service = SipService();
  final _formKey = GlobalKey<FormState>();

  final _serverUrl = TextEditingController(text: JanusConfig.defaultServerUrl);
  final _apiSecret = TextEditingController(text: JanusConfig.defaultApiSecret);
  final _extension = TextEditingController();
  final _password = TextEditingController();

  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    _serverUrl.dispose();
    _apiSecret.dispose();
    _extension.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 등록은 SipRegisteredEvent 로 완료되므로 상태 변화를 보고 넘어간다.
  void _onServiceChanged() {
    if (!mounted || _navigated) return;
    if (!_service.isRegistered) return;

    _navigated = true;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => DialerScreen(service: _service),
        ))
        .then((_) => _navigated = false);
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await _service.connectAndRegister(
      serverUrl: _serverUrl.text.trim(),
      apiSecret: _apiSecret.text.trim(),
      extension: _extension.text.trim(),
      password: _password.text,
    );
  }

  void _openEchoTest() {
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
      body: AuroraBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _service,
            builder: (context, _) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(context),
                    const SizedBox(height: 28),
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
                                  'WebSocket 은 /janus-ws · REST 는 /janus-api',
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
                              labelText: 'API Secret',
                              helperText: '없으면 모든 요청이 403 으로 거절됩니다',
                              prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
                            ),
                            validator: (v) => _required(v, 'API Secret'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionLabel('SIP 계정',
                              icon: Icons.badge_outlined),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _extension,
                            keyboardType: TextInputType.text,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: '내선 번호',
                              helperText: 'Kamailio 에 만든 계정 (예: 1001)',
                              prefixIcon: Icon(Icons.dialpad, size: 20),
                            ),
                            validator: (v) => _required(v, '내선 번호'),
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _password,
                            obscureText: true,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: '계정 비밀번호',
                              prefixIcon: Icon(Icons.lock_outline, size: 20),
                            ),
                            validator: (v) => _required(v, '비밀번호'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildStatus(context),
                    GlowButton(
                      label: _busy ? '등록 중…' : 'SIP 등록',
                      icon: Icons.login,
                      busy: _busy,
                      onPressed: _register,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openEchoTest,
                      icon: const Icon(Icons.graphic_eq, size: 18),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('EchoTest 로 연결만 확인'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 아이콘의 통화 마크를 그대로 첫 화면 대문으로 쓴다.
  Widget _buildHero(BuildContext context) {
    return Column(
      children: [
        const JanusMark(width: 168),
        const SizedBox(height: 4),
        const Text(
          'Janus Client',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '인터폰 통화 · SIP over WebRTC',
          style: TextStyle(
            fontSize: 13,
            color: AppPalette.mist.withValues(alpha: 0.72),
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  bool get _busy =>
      _service.registrationState == SipRegistrationState.connecting ||
      _service.registrationState == SipRegistrationState.registering;

  Widget _buildStatus(BuildContext context) {
    final message = _service.errorMessage;
    if (message != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: StatusPill(
          tone: StatusTone.danger,
          icon: Icons.error_outline,
          message: message,
        ),
      );
    }
    if (!_busy) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: StatusPill(
        tone: StatusTone.info,
        busy: true,
        message: '서버에 등록하는 중…',
      ),
    );
  }
}
