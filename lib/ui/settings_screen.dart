import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/janus_config.dart';

import '../services/complex_directory.dart';
import '../services/credential_store.dart';
import 'complex_picker_screen.dart';
import 'echo_test_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';

/// 단지와 세대를 받아 기기에 저장한다.
///
/// **내선 번호와 비밀번호는 더 이상 받지 않는다.** 서버가 승인 시점에 동/호에서
/// 번호를 계산해 배정하고 Kamailio 계정까지 만들며, 앱은 등록 응답으로 받은 값을
/// 쓰기만 한다 (client-migration.md). 등록은 호출한 쪽(ConnectScreen)이 맡는다.
///
/// 이 화면에는 마크를 두지 않는다 — 입력에 집중시키기 위해서다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.initial});

  final DeviceProfile initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _store = const CredentialStore();

  late final _email = TextEditingController(text: widget.initial.email);
  late final _building = TextEditingController(text: widget.initial.building);
  late final _unit = TextEditingController(text: widget.initial.unit);
  // 빌드에 주입된 값이 있으면 그걸로 채운다
  // (--dart-define=JANUS_API_SECRET=...).
  late final _apiSecret = TextEditingController(
    text: widget.initial.apiSecret.isEmpty
        ? JanusConfig.defaultApiSecret
        : widget.initial.apiSecret,
  );

  late String _complexId = widget.initial.complexId;
  late String _complexName = widget.initial.complexName;
  late String _complexHost = widget.initial.complexHost;

  bool _saving = false;

  @override
  void dispose() {
    _email.dispose();
    _building.dispose();
    _unit.dispose();
    _apiSecret.dispose();
    super.dispose();
  }

  Future<void> _pickComplex() async {
    final complex = await Navigator.of(context).push<ComplexRef>(
      MaterialPageRoute<ComplexRef>(builder: (_) => const ComplexPickerScreen()),
    );
    if (!mounted || complex == null) return;
    setState(() {
      _complexId = complex.complexId;
      _complexName = complex.name;
      _complexHost = complex.host;
    });
  }

  Future<void> _pasteApiSecret() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('클립보드가 비어 있습니다')),
      );
      return;
    }
    _apiSecret.text = text;
  }

  Future<void> _save() async {
    if (_complexHost.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 단지를 고르세요')),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final profile = widget.initial.copyWith(
      email: _email.text.trim(),
      complexId: _complexId,
      complexName: _complexName,
      complexHost: _complexHost,
      building: _building.text.trim(),
      unit: _unit.text.trim(),
      apiSecret: _apiSecret.text.trim(),
    );
    await _store.save(profile);

    if (!mounted) return;
    Navigator.of(context).pop(profile);
  }

  void _openEchoTest() {
    if (_complexHost.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 단지를 고르세요')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EchoTestScreen(
          serverUrl: 'wss://$_complexHost/janus-ws',
          apiSecret: _apiSecret.text.trim(),
        ),
      ),
    );
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label을(를) 입력하세요';
    return null;
  }

  String? _digits(String? value, String label) {
    final base = _required(value, label);
    if (base != null) return base;
    if (!RegExp(r'^\d+$').hasMatch(value!.trim())) return '$label은(는) 숫자만 넣습니다';
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
                        const SectionLabel('단지', icon: Icons.apartment_outlined),
                        const SizedBox(height: 16),
                        _ComplexRow(
                          name: _complexName,
                          host: _complexHost,
                          onTap: _pickComplex,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _apiSecret,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'API Secret',
                            helperText: '없으면 모든 요청이 403 으로 거절됩니다',
                            prefixIcon:
                                const Icon(Icons.vpn_key_outlined, size: 20),
                            // 32자리 16진수를 손으로 치게 두지 않는다.
                            suffixIcon: IconButton(
                              tooltip: '붙여넣기',
                              icon: const Icon(Icons.content_paste, size: 20),
                              onPressed: _pasteApiSecret,
                            ),
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
                        const SectionLabel('세대', icon: Icons.home_outlined),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _building,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '동',
                                  hintText: '101',
                                ),
                                validator: (v) => _digits(v, '동'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _unit,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '호',
                                  hintText: '805',
                                ),
                                validator: (v) => _digits(v, '호'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 서버가 받는 유일한 형태다. 사용자가 형식을 외울 필요가
                        // 없도록 조립 결과를 그대로 보여 준다.
                        ListenableBuilder(
                          listenable: Listenable.merge([_building, _unit]),
                          builder: (context, _) => Text(
                            '서버에 보낼 주소: '
                            '${_building.text.trim()}B${_unit.text.trim()}U',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: '이메일',
                            prefixIcon: Icon(Icons.mail_outline, size: 20),
                          ),
                          validator: (v) => _required(v, '이메일'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '내선 번호와 비밀번호는 서버가 동/호에서 계산해 배정합니다.\n'
                    '입력한 값은 이 기기에만 저장됩니다.',
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

class _ComplexRow extends StatelessWidget {
  const _ComplexRow({
    required this.name,
    required this.host,
    required this.onTap,
  });

  final String name;
  final String host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chosen = host.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: chosen ? AppPalette.glassStroke : AppPalette.warning,
            ),
            color: AppPalette.glassFillSoft,
          ),
          child: Row(
            children: [
              Icon(
                chosen ? Icons.apartment : Icons.search,
                size: 20,
                color: chosen ? AppPalette.cyan : AppPalette.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  chosen ? name : '단지를 고르세요',
                  style: TextStyle(
                    fontSize: 15,
                    color: chosen ? Colors.white : AppPalette.warning,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
