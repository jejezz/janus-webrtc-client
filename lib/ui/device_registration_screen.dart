import 'package:flutter/material.dart';

import '../config/janus_config.dart';
import '../services/device_registration_service.dart';

/// 착신을 받기 위해 FCM 토큰과 SIP 내선을 rtc-relay 에 등록한다.
///
/// 이걸 하지 않으면 인터폰이 걸어도 깨울 단말을 찾지 못한다.
///
/// FCM 토큰 자동 조회는 아직 붙어 있지 않다. `firebase_messaging` 과 Firebase
/// 프로젝트의 `google-services.json` 이 있어야 해서, 지금은 토큰을 직접 넣어
/// 서버 연동만 먼저 검증할 수 있게 해 두었다.
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
      appBar: AppBar(title: const Text('착신용 단말 등록')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '인터폰이 걸었을 때 이 단말을 깨우려면 FCM 토큰과 내선 번호가 '
                  '서버에 이어져 있어야 합니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                _field(_uuid, '단말 고유 id (uuid)', required: true),
                _field(_email, '이메일', required: true),
                _field(_complex, '단지(complex)', required: true),
                _field(_address, '주소(address)', required: true),
                _field(
                  _token,
                  'FCM 토큰',
                  required: true,
                  helper: 'firebase_messaging 연동 전까지는 직접 붙여 넣습니다',
                  maxLines: 3,
                ),
                _field(
                  _sipUser,
                  'sip_user (내선)',
                  helper: 'Kamailio 내선과 반드시 같아야 합니다. 비우면 기존 값 유지',
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return null;
                    if (!DeviceRegistrationService.isValidSipUser(value)) {
                      return 'A-Z a-z 0-9 . _ - 만 64자까지 쓸 수 있습니다';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.cloud_upload),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_busy ? '등록 중…' : '단말 등록'),
                  ),
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
      padding: const EdgeInsets.only(bottom: 16),
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
    final color = result.ok ? Colors.greenAccent : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.ok ? Icons.check_circle : Icons.error_outline,
              color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(result.message,
                style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
