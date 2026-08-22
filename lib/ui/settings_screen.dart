import 'package:flutter/material.dart';

import '../config/janus_config.dart';
import '../services/credential_store.dart';
import 'echo_test_screen.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';

/// 서버 접속 정보와 SIP 계정을 입력받아 기기에 저장한다.
///
/// 저장이 끝나면 입력값을 돌려주고 닫힌다. 등록은 호출한 쪽(ConnectScreen)이
/// 맡는다. 이 화면에는 마크를 두지 않는다 — 입력에 집중시키기 위해서다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.initial});

  final SipCredentials initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _store = const CredentialStore();

  late final _serverUrl = TextEditingController(
    text: widget.initial.serverUrl.isEmpty
        ? JanusConfig.defaultServerUrl
        : widget.initial.serverUrl,
  );
  late final _apiSecret = TextEditingController(
    text: widget.initial.apiSecret.isEmpty
        ? JanusConfig.defaultApiSecret
        : widget.initial.apiSecret,
  );
  late final _extension = TextEditingController(text: widget.initial.extension);
  late final _password = TextEditingController(text: widget.initial.password);

  bool _saving = false;

  @override
  void dispose() {
    _serverUrl.dispose();
    _apiSecret.dispose();
    _extension.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final credentials = SipCredentials(
      serverUrl: _serverUrl.text.trim(),
      apiSecret: _apiSecret.text.trim(),
      extension: _extension.text.trim(),
      password: _password.text,
    );
    await _store.save(credentials);

    if (!mounted) return;
    Navigator.of(context).pop(credentials);
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('설정')),
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
                  const SizedBox(height: 12),
                  const Text(
                    '입력한 값은 이 기기에만 저장됩니다 (iOS 키체인 · Android 암호화 저장소).',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: Colors.white38),
                  ),
                  const SizedBox(height: 20),
                  GlowButton(
                    label: _saving ? '저장 중…' : '저장하고 등록',
                    icon: Icons.save_outlined,
                    busy: _saving,
                    onPressed: _save,
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
    );
  }
}
