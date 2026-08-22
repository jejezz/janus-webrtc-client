import 'package:flutter/material.dart';

import '../config/janus_config.dart';
import '../services/sip_service.dart';
import 'dialer_screen.dart';
import 'echo_test_screen.dart';

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
      appBar: AppBar(title: const Text('인터폰 통화')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _service,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _serverUrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Janus 시그널링 주소',
                      helperText: 'WebSocket 은 /janus-ws · REST 는 /janus-api',
                      border: OutlineInputBorder(),
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _apiSecret,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'API Secret',
                      helperText: '없으면 모든 요청이 403 으로 거절됩니다',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => _required(v, 'API Secret'),
                  ),
                  const Divider(height: 40),
                  TextFormField(
                    controller: _extension,
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '내선 번호',
                      helperText: 'Kamailio 에 만든 계정 (예: 1001)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => _required(v, '내선 번호'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '계정 비밀번호',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => _required(v, '비밀번호'),
                  ),
                  const SizedBox(height: 24),
                  _buildStatus(context),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _register,
                    icon: const Icon(Icons.login),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_busy ? '등록 중…' : 'SIP 등록'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openEchoTest,
                    icon: const Icon(Icons.graphic_eq),
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
    );
  }

  bool get _busy =>
      _service.registrationState == SipRegistrationState.connecting ||
      _service.registrationState == SipRegistrationState.registering;

  Widget _buildStatus(BuildContext context) {
    final message = _service.errorMessage;
    if (message == null) {
      if (!_busy) return const SizedBox.shrink();
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('서버에 등록하는 중…'),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
