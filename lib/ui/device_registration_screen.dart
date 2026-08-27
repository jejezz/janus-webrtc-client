import 'package:flutter/material.dart';

import '../config/janus_config.dart';
import '../services/device_registration_service.dart';
import '../services/push_service.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';

/// 착신을 받기 위해 FCM 토큰과 SIP 내선을 rtc-relay 에 등록한다.
///
/// 이걸 하지 않으면 인터폰이 걸어도 깨울 단말을 찾지 못한다.
///
/// FCM 토큰은 앱이 알아서 채운다. 다만 `google-services.json` 이 없으면 토큰을
/// 얻을 수 없으므로, 그때는 비워 두고 직접 붙여 넣을 수 있게 남겨 둔다.
class DeviceRegistrationScreen extends StatefulWidget {
  const DeviceRegistrationScreen({super.key, this.defaultSipUser});

  final String? defaultSipUser;

  @override
  State<DeviceRegistrationScreen> createState() =>
      _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  final _service = DeviceRegistrationService();
  final _formKey = GlobalKey<FormState>();

  final _uuid = TextEditingController();
  final _email = TextEditingController();
  final _complex = TextEditingController();
  final _address = TextEditingController();
  final _token = TextEditingController();
  late final _sipUser = TextEditingController(text: widget.defaultSipUser ?? '');

  bool _busy = false;
  DeviceRegistrationResult? _result;

  /// FCM 을 쓸 수 없어 토큰을 못 채운 상태.
  bool _tokenUnavailable = false;

  @override
  void initState() {
    super.initState();
    _fillToken();
  }

  /// 이 단말의 FCM 토큰을 채워 둔다. 사용자가 어디서 복사해 올 값이 아니다.
  Future<void> _fillToken() async {
    final token = await PushService.token();
    if (!mounted) return;
    setState(() {
      if (token != null) {
        _token.text = token;
      } else {
        _tokenUnavailable = true;
      }
    });
  }

  @override
  void dispose() {
    _service.dispose();
    _uuid.dispose();
    _email.dispose();
    _complex.dispose();
    _address.dispose();
    _token.dispose();
    _sipUser.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _result = null;
    });

    final result = await _service.registerMobile(
      uuid: _uuid.text.trim(),
      email: _email.text.trim(),
      complex: _complex.text.trim(),
      address: _address.text.trim(),
      fcmToken: _token.text.trim(),
      sipUser: _sipUser.text.trim().isEmpty ? null : _sipUser.text.trim(),
      signalingUrl: JanusConfig.defaultServerUrl,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label을(를) 입력하세요';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('착신용 단말 등록')),
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const StatusPill(
                    tone: StatusTone.info,
                    icon: Icons.info_outline,
                    message: '인터폰이 걸었을 때 이 단말을 깨우려면 FCM 토큰과 '
                        '내선 번호가 서버에 이어져 있어야 합니다.',
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionLabel('단말 정보',
                            icon: Icons.smartphone_outlined),
                        const SizedBox(height: 16),
                        _field(_uuid, '단말 고유 id (uuid)', required: true),
                        _field(_email, '이메일', required: true),
                        _field(_complex, '단지(complex)', required: true),
                        _field(_address, '주소(address)', required: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionLabel('착신 연결',
                            icon: Icons.notifications_active_outlined),
                        const SizedBox(height: 16),
                        _field(
                          _token,
                          'FCM 토큰',
                          required: true,
                          helper: _tokenUnavailable
                              ? 'google-services.json 이 없어 토큰을 얻지 못했습니다. '
                                  '직접 붙여 넣으세요'
                              : '이 단말의 토큰을 자동으로 채웁니다',
                          maxLines: 3,
                        ),
                        _field(
                          _sipUser,
                          'sip_user (내선)',
                          helper: 'Kamailio 내선과 반드시 같아야 합니다. 비우면 기존 값 유지',
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.isEmpty) return null;
                            if (!DeviceRegistrationService.isValidSipUser(
                              value,
                            )) {
                              return 'A-Z a-z 0-9 . _ - 만 64자까지 쓸 수 있습니다';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  GlowButton(
                    label: _busy ? '등록 중…' : '단말 등록',
                    icon: Icons.cloud_upload,
                    busy: _busy,
                    onPressed: _submit,
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 20),
                    _buildResult(context, _result!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    String? helper,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        autocorrect: false,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        validator: validator ?? (required ? (v) => _required(v, label) : null),
      ),
    );
  }

  Widget _buildResult(BuildContext context, DeviceRegistrationResult result) {
    return StatusPill(
      tone: result.ok ? StatusTone.success : StatusTone.danger,
      icon: result.ok ? Icons.check_circle : Icons.error_outline,
      message: result.message,
    );
  }
}
