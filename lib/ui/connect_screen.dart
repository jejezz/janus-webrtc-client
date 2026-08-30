import 'package:flutter/material.dart';

import '../models/sip_account.dart';
import '../services/credential_store.dart';
import '../services/device_registration_service.dart';
import '../services/push_service.dart';
import '../services/sip_service.dart';
import 'dialer_screen.dart';
import 'settings_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';
import 'widgets/janus_mark.dart';

/// 앱의 첫 화면. 저장된 단지·세대로 자격을 받아 등록까지 밀고 간다.
///
/// 순서가 정해져 있다 (client-migration.md).
///
/// ```
/// /register/mobile  →  sip{user,domain,password}  →  Janus register
/// ```
///
/// 앱이 내선 번호를 정하지 않는다. 서버가 동/호에서 계산해 배정한 값을 받아 쓸
/// 뿐이고, 비밀번호는 자리를 물려받은 단말이 생기면 새로 발급되므로 401 을
/// 만나면 한 번 더 받아서 다시 등록한다.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final SipService _service = SipService();
  final CredentialStore _store = const CredentialStore();
  final DeviceRegistrationService _enrollment = DeviceRegistrationService();

  late final AppLifecycleListener _lifecycle;

  DeviceProfile _profile = const DeviceProfile.empty();

  bool _loading = true;
  bool _enrolling = false;
  bool _navigated = false;

  /// 사용자가 직접 등록을 해제하고 돌아온 상태. 이때는 자동 등록하지 않는다.
  bool _manual = false;

  /// 401 재발급은 한 번만. 계속 401 이면 자격이 아니라 계정 문제다.
  bool _retriedAfter401 = false;

  /// 등록까지 가지 못한 이유. 화면에 그대로 보여 준다.
  String? _blocker;

  /// 승인 대기 등, 사용자가 기다리는 것 말고 할 일이 없는 상태.
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    // Janus 등록 만료는 10분이다. 앱이 사라진 뒤 그 시간이 지나야 Kamailio 가
    // "없음" 으로 보고 다시 푸시를 건다 — 그 사이 착신은 죽은 세션으로 간다.
    // 종료할 때 세션을 명시적으로 닫으면 그 창이 사라진다.
    _lifecycle = AppLifecycleListener(onDetach: _service.disconnect);
    PushService.enrollmentEvent.addListener(_onEnrollmentEvent);
    _bootstrap();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    PushService.enrollmentEvent.removeListener(_onEnrollmentEvent);
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    _enrollment.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final profile = await _store.load();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
    if (profile.isComplete) {
      _enrollAndRegister();
    } else {
      _openSettings();
    }
  }

  /// 월패드가 승인·거절했을 때. 승인 결과는 푸시로만 온다.
  void _onEnrollmentEvent() {
    final method = PushService.enrollmentEvent.value;
    if (method == null || !mounted) return;
    PushService.enrollmentEvent.value = null;
    debugPrint('[등록] 승인 이벤트 $method');

    switch (method) {
      case 'enroll.approved':
        // 승인됐으니 자격을 받으러 다시 간다.
        _enrollAndRegister();
      case 'enroll.rejected':
        setState(() {
          _pending = false;
          _blocker = '월패드에서 이 단말의 등록을 거절했습니다.\n'
              '세대와 이메일을 확인한 뒤 다시 요청하세요.';
        });
      case 'enroll.expired':
        setState(() {
          _pending = false;
          _blocker = '30분 안에 승인되지 않아 요청이 사라졌습니다.\n'
              '다시 요청해 주세요.';
        });
    }
  }

  /// 자격을 받아 Janus 에 등록한다.
  Future<void> _enrollAndRegister() async {
    if (!_profile.isComplete || _enrolling) return;
    setState(() {
      _manual = false;
      _pending = false;
      _blocker = null;
      _enrolling = true;
    });

    debugPrint('[등록] relay=${_profile.relayUrl} janus=${_profile.janusUrl}');
    final account = await _fetchAccount();
    if (!mounted) return;
    setState(() => _enrolling = false);
    if (account == null) return;   // 이유는 _blocker 에 담겼다

    debugPrint('[등록] 자격 확보 user=${account.user} domain=${account.domain} '
        '→ Janus 등록 시작');
    await _service.connectAndRegister(
      serverUrl: _profile.janusUrl,
      apiSecret: _profile.apiSecret,
      account: account,
    );
  }

  /// `/register/mobile` 로 SIP 자격을 받아 온다.
  Future<SipAccount?> _fetchAccount() async {
    final token = await PushService.token();
    debugPrint('[등록] FCM 토큰 ${token == null ? '없음' : '확보(${token.length}자)'}');
    if (token == null) {
      // 이 호출은 저장된 토큰을 덮어쓴다. 빈 값을 보내면 그 단말의 푸시가 조용히
      // 끊기므로 아예 부르지 않는다.
      final cached = _profile.sip;
      if (cached != null) return cached;
      setState(() => _blocker =
          'FCM 토큰을 얻지 못해 서버에 자격을 요청할 수 없습니다.\n'
          'google-services.json 을 넣고 다시 실행하세요.');
      return null;
    }

    final result = await _enrollment.registerMobile(
      uuid: _profile.uuid,
      email: _profile.email,
      complex: _profile.complexId,
      address: _profile.address,
      fcmToken: token,
      relayUrl: _profile.relayUrl,
    );
    if (!mounted) return null;

    if (!result.ok) {
      setState(() => _blocker = result.message);
      return null;
    }
    if (result.isPending) {
      setState(() {
        _pending = true;
        _blocker = result.message;
      });
      return null;
    }

    final account = result.account;
    if (account == null) {
      setState(() => _blocker = result.message);
      return null;
    }

    await _store.saveSip(account);
    if (mounted) setState(() => _profile = _profile.copyWith(sip: account));
    return account;
  }

  /// 등록은 SipRegisteredEvent 로 완료되므로 상태 변화를 보고 넘어간다.
  Future<void> _onServiceChanged() async {
    if (!mounted) return;

    // 비밀번호가 바뀌면 401 이 온다. 자격을 다시 받아 한 번 더 시도한다.
    if (_service.registrationState == SipRegistrationState.failed &&
        _service.registrationFailureCode == 401 &&
        !_retriedAfter401) {
      _retriedAfter401 = true;
      await _store.saveSip(null);
      _profile = _profile.copyWith(sip: null);
      _enrollAndRegister();
      return;
    }

    if (_navigated || !_service.isRegistered) return;
    _retriedAfter401 = false;

    _navigated = true;
    final exit = await Navigator.of(context).push<DialerExit>(
      MaterialPageRoute<DialerExit>(
        builder: (_) => DialerScreen(service: _service),
      ),
    );
    if (!mounted) return;
    setState(() => _navigated = false);

    if (exit == DialerExit.connectionLost) {
      _enrollAndRegister();
      return;
    }
    setState(() => _manual = true);
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<DeviceProfile>(
      MaterialPageRoute<DeviceProfile>(
        builder: (_) => SettingsScreen(initial: _profile),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _profile = result);
    _enrollAndRegister();
  }

  bool get _busy =>
      _enrolling ||
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
                          _subtitle,
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

  String get _subtitle {
    final sip = _profile.sip;
    if (sip != null) return '내선 ${sip.user} · ${sip.domain}';
    if (_profile.complexName.isNotEmpty) {
      return '${_profile.complexName} · ${_profile.building}동 ${_profile.unit}호';
    }
    return '인터폰 통화 · SIP over WebRTC';
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
      return [
        StatusPill(
          tone: StatusTone.info,
          busy: true,
          message: _enrolling ? '서버에서 자격을 받는 중…' : '서버에 등록하는 중…',
        ),
      ];
    }

    // 승인 대기처럼 사용자가 기다리는 것 말고 할 일이 없는 상태.
    if (_pending) {
      return [
        StatusPill(
          tone: StatusTone.warning,
          icon: Icons.hourglass_bottom,
          message: '${_blocker ?? '승인 대기 중입니다.'}\n'
              '승인되면 자동으로 넘어갑니다. 30분 안에 승인되지 않으면 요청이 사라집니다.',
        ),
        const SizedBox(height: 20),
        GlowButton(
          label: '다시 확인',
          icon: Icons.refresh,
          onPressed: _enrollAndRegister,
        ),
        const SizedBox(height: 12),
        _settingsButton(),
      ];
    }

    final blocker = _blocker;
    if (blocker != null || _failed) {
      return [
        StatusPill(
          tone: StatusTone.danger,
          icon: Icons.error_outline,
          message: blocker ?? _service.errorMessage ?? '등록에 실패했습니다',
        ),
        const SizedBox(height: 20),
        GlowButton(
          label: '설정 열기',
          icon: Icons.settings_outlined,
          onPressed: _openSettings,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _enrollAndRegister,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('다시 시도'),
          ),
        ),
      ];
    }

    if (!_profile.isComplete) {
      return [
        const StatusPill(
          tone: StatusTone.warning,
          icon: Icons.settings_suggest_outlined,
          message: '단지와 세대를 먼저 설정하세요.',
        ),
        const SizedBox(height: 20),
        GlowButton(
          label: '설정 열기',
          icon: Icons.settings_outlined,
          onPressed: _openSettings,
        ),
      ];
    }

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
        onPressed: _enrollAndRegister,
      ),
      const SizedBox(height: 12),
      _settingsButton(),
    ];
  }

  Widget _settingsButton() {
    return OutlinedButton.icon(
      onPressed: _openSettings,
      icon: const Icon(Icons.settings_outlined, size: 18),
      label: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('설정 열기'),
      ),
    );
  }
}
