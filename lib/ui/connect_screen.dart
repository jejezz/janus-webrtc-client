import 'package:flutter/material.dart';

import '../config/sip_config.dart';
import '../services/credential_store.dart';
import '../services/sip_service.dart';
import 'dialer_screen.dart';
import 'settings_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';
import 'widgets/janus_mark.dart';

/// 앱의 첫 화면. 저장된 접속 정보로 등록까지 밀고 간다.
///
/// 저장된 값이 있으면 사용자 개입 없이 바로 등록하고, 없으면 설정 화면을 연다.
/// 등록에 실패하면 원인과 함께 설정으로 갈 수 있는 길을 보여 준다.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final SipService _service = SipService();
  final CredentialStore _store = const CredentialStore();

  SipCredentials _credentials = const SipCredentials.empty();

  /// 저장된 값을 읽는 동안.
  bool _loading = true;

  /// 다이얼러로 넘어가 있는 동안 중복 이동을 막는다.
  bool _navigated = false;

  /// 사용자가 직접 등록을 해제하고 돌아온 상태. 이때는 자동 등록하지 않는다.
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final saved = await _store.load();
    if (!mounted) return;
    setState(() {
      _credentials = saved;
      _loading = false;
    });
    if (saved.isComplete) {
      _register();
    } else {
      _openSettings();
    }
  }

  /// 등록은 SipRegisteredEvent 로 완료되므로 상태 변화를 보고 넘어간다.
  Future<void> _onServiceChanged() async {
    if (!mounted || _navigated) return;
    if (!_service.isRegistered) return;

    _navigated = true;
    final exit = await Navigator.of(context).push<DialerExit>(
      MaterialPageRoute<DialerExit>(
        builder: (_) => DialerScreen(service: _service),
      ),
    );
    if (!mounted) return;
    setState(() => _navigated = false);

    if (exit == DialerExit.connectionLost) {
      // 사용자가 끊은 게 아니라 시그널링이 죽은 것이다. 조용히 다시 붙는다.
      _register();
      return;
    }
    setState(() => _manual = true);
  }

  Future<void> _register() async {
    if (!_credentials.isComplete) return;
    setState(() => _manual = false);
    await _service.connectAndRegister(
      serverUrl: _credentials.serverUrl,
      apiSecret: _credentials.apiSecret,
      extension: _credentials.extension,
      password: _credentials.password,
    );
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<SipCredentials>(
      MaterialPageRoute<SipCredentials>(
        builder: (_) => SettingsScreen(initial: _credentials),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _credentials = result);
    _register();
  }

  bool get _busy =>
      _service.registrationState == SipRegistrationState.connecting ||
      _service.registrationState == SipRegistrationState.registering;

  bool get _failed =>
      _service.registrationState == SipRegistrationState.failed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _service,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight - 40),
                  // Spacer 는 높이가 확정돼야 동작한다. 스크롤 안에서는
                  // IntrinsicHeight 가 그 높이를 잡아 준다.
                  child: IntrinsicHeight(
                    child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),
                  const JanusMark(width: 180),
                  const SizedBox(height: 8),
                  const Text(
                    'Janus Client',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _credentials.extension.isEmpty
                        ? '인터폰 통화 · SIP over WebRTC'
                        : '내선 ${_credentials.extension} · ${SipConfig.domain}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.mist.withValues(alpha: 0.72),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(flex: 3),
                  ..._buildStatus(context),
                ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStatus(BuildContext context) {
    if (_loading) {
      return const [
        StatusPill(
          tone: StatusTone.info,
          busy: true,
          message: '저장된 접속 정보를 확인하는 중…',
        ),
      ];
    }

    if (_busy) {
      return const [
        StatusPill(
          tone: StatusTone.info,
          busy: true,
          message: '서버에 등록하는 중…',
        ),
      ];
    }

    if (_failed) {
      return [
        StatusPill(
          tone: StatusTone.danger,
          icon: Icons.error_outline,
          message: _service.errorMessage ?? '등록에 실패했습니다',
        ),
        const SizedBox(height: 20),
        GlowButton(
          label: '설정 열기',
          icon: Icons.settings_outlined,
          onPressed: _openSettings,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _register,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('다시 시도'),
          ),
        ),
      ];
    }

    if (!_credentials.isComplete) {
      return [
        const StatusPill(
          tone: StatusTone.warning,
          icon: Icons.settings_suggest_outlined,
          message: '접속 정보가 아직 없습니다. 설정에서 서버와 계정을 입력하세요.',
        ),
        const SizedBox(height: 20),
        GlowButton(
          label: '설정 열기',
          icon: Icons.settings_outlined,
          onPressed: _openSettings,
        ),
      ];
    }

    // 등록을 해제하고 돌아온 상태.
    return [
      StatusPill(
        tone: StatusTone.neutral,
        icon: Icons.pause_circle_outline,
        message: _manual ? '등록이 해제되었습니다' : '등록 대기 중',
      ),
      const SizedBox(height: 20),
      GlowButton(
        label: 'SIP 등록',
        icon: Icons.login,
        onPressed: _register,
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _openSettings,
        icon: const Icon(Icons.settings_outlined, size: 18),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('설정 열기'),
        ),
      ),
    ];
  }
}
