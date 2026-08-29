import 'package:flutter/material.dart';

import '../services/credential_store.dart';
import '../services/device_registration_service.dart';
import '../services/push_service.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';

/// 이 단말이 서버에 어떻게 등록돼 있는지 보여 주고, 다시 등록할 수 있게 한다.
///
/// 값을 입력받지 않는다 — 단지·세대는 설정 화면이, 내선 번호는 서버가 정한다.
/// 여기서 하는 일은 저장된 프로필로 `/register/mobile` 을 한 번 더 부르는 것뿐이다.
/// 자리를 물려받아 비밀번호가 새로 발급됐을 때 손으로 되살리는 길이기도 하다.
class DeviceRegistrationScreen extends StatefulWidget {
  const DeviceRegistrationScreen({super.key});

  @override
  State<DeviceRegistrationScreen> createState() =>
      _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  final _store = const CredentialStore();
  final _service = DeviceRegistrationService();

  DeviceProfile _profile = const DeviceProfile.empty();
  String? _token;
  bool _loading = true;
  bool _busy = false;
  DeviceRegistrationResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _store.load();
    final token = await PushService.token();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _token = token;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      // 이 호출은 저장된 토큰을 덮어쓴다. 빈 값을 보내면 그 단말의 푸시가
      // 조용히 끊기므로 아예 보내지 않는다.
      setState(() => _result = const DeviceRegistrationResult(
            ok: false,
            statusCode: 0,
            message: 'FCM 토큰이 없어 등록하지 않았습니다.\n'
                '빈 값으로 보내면 이 단말의 푸시가 끊깁니다.',
          ));
      return;
    }

    setState(() {
      _busy = true;
      _result = null;
    });

    final result = await _service.registerMobile(
      uuid: _profile.uuid,
      email: _profile.email,
      complex: _profile.complexId,
      address: _profile.address,
      fcmToken: token,
      signalingUrl: _profile.janusUrl,
    );
    if (result.account != null) await _store.saveSip(result.account);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (result.account != null) {
        _profile = _profile.copyWith(sip: result.account);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('단말 등록 상태')),
      body: AuroraBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionLabel('이 단말',
                                icon: Icons.smartphone_outlined),
                            const SizedBox(height: 14),
                            _row('단지', _profile.complexName),
                            _row('세대', _profile.address),
                            _row('이메일', _profile.email),
                            _row('단말 id', _profile.uuid),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionLabel('서버가 배정한 것',
                                icon: Icons.badge_outlined),
                            const SizedBox(height: 14),
                            _row('내선', _profile.sip?.user ?? '아직 없음'),
                            _row('도메인', _profile.sip?.domain ?? '—'),
                            _row(
                              'FCM 토큰',
                              _token == null
                                  ? '없음 (google-services.json 필요)'
                                  : '${_token!.substring(0, _token!.length.clamp(0, 24))}…',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '내선 번호는 서버가 동/호에서 계산해 배정합니다.\n'
                        '비밀번호가 바뀌어 등록이 401 로 거절되면 여기서 다시 받으세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: Colors.white38),
                      ),
                      const SizedBox(height: 20),
                      GlowButton(
                        label: _busy ? '등록 중…' : '서버에 다시 등록',
                        icon: Icons.cloud_upload,
                        busy: _busy,
                        onPressed: _submit,
                      ),
                      if (_result != null) ...[
                        const SizedBox(height: 20),
                        StatusPill(
                          tone: _result!.ok
                              ? StatusTone.success
                              : StatusTone.danger,
                          icon: _result!.ok
                              ? Icons.check_circle
                              : Icons.error_outline,
                          message: _result!.message,
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
