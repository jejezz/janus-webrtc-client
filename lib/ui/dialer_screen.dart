import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/sip_config.dart';
import '../services/sip_service.dart';
import 'device_registration_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';
import 'widgets/dial_pad.dart';
import 'widgets/janus_mark.dart';
import 'widgets/pulse_avatar.dart';

/// 다이얼러를 벗어난 이유. 호출한 쪽이 재등록할지 말지 가른다.
enum DialerExit {
  /// 사용자가 직접 등록을 해제했다.
  userEnded,

  /// 시그널링이 끊겨 등록이 풀렸다. 다시 등록해야 한다.
  connectionLost,
}

/// 등록이 끝난 뒤의 화면. 발신과 착신 응답을 모두 여기서 처리한다.
class DialerScreen extends StatefulWidget {
  const DialerScreen({
    super.key,
    required this.service,
    this.defaultCallee = '',
  });

  final SipService service;

  /// 미리 채워 둘 상대 번호. 우리 집 월패드를 향한다.
  final String defaultCallee;

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  late final TextEditingController _callee = TextEditingController(
    text: widget.defaultCallee.isNotEmpty
        ? widget.defaultCallee
        : SipConfig.defaultCallee,
  );

  /// 통화 시간 표시를 1초마다 갱신한다.
  Timer? _ticker;

  /// 중복 pop 을 막는다.
  bool _leaving = false;

  /// 키패드를 펼쳐 둘지. 전화 거는 화면이므로 기본은 펼침이다.
  bool _keypadOpen = true;

  /// 통화 중 키패드. DTMF 를 보내는 자리다.
  ///
  /// 문 열기가 이 경로인지는 확인되지 않았다. 안드로이드 원본의 문열림 버튼은
  /// 안내음을 내고 통화를 끊을 뿐 선로로 아무것도 내보내지 않는다 —
  /// `CallSession.doorOpen()` 안의 `DeviceManager.setDoorOpen()` 이 주석 처리된
  /// 채로 남아 있다. 실제로 문을 여는 쪽은 월패드다.
  bool _inCallKeypad = false;

  /// 입력칸 좌우에 같은 폭을 둬야 번호가 가운데에 선다. 좁게 잡는다 — 양쪽에
  /// 48 씩 두면 10자리 번호가 들어갈 자리가 모자라 잘린다.
  static const BoxConstraints _affixSize =
      BoxConstraints(minWidth: 40, minHeight: 40);

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.service.callState == CallState.active) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    _ticker?.cancel();
    _callee.dispose();
    super.dispose();
  }

  /// 등록이 풀리면 이 화면은 아무것도 할 수 없다. 등록 화면으로 돌려보내
  /// 다시 붙게 한다.
  void _onServiceChanged() {
    if (!mounted || _leaving) return;
    if (_inCallKeypad && widget.service.callState != CallState.active) {
      setState(() => _inCallKeypad = false);
    }
    if (widget.service.registrationState != SipRegistrationState.failed) return;
    _leaving = true;
    Navigator.of(context).pop(DialerExit.connectionLost);
  }

  void _appendDigit(String digit) {
    // 통화 중에는 같은 키패드가 DTMF 를 보낸다.
    if (widget.service.callState == CallState.active) {
      widget.service.sendDtmf(digit);
      return;
    }
    _callee.text += digit;
    setState(() {});
  }

  void _backspace() {
    if (_callee.text.isEmpty) return;
    _callee.text = _callee.text.substring(0, _callee.text.length - 1);
    setState(() {});
  }

  void _clearCallee() {
    if (_callee.text.isEmpty) return;
    _callee.clear();
    setState(() {});
  }

  void _dial({required bool video}) {
    final target = _callee.text.trim();
    if (target.isEmpty) return;
    FocusScope.of(context).unfocus();
    widget.service.call(target, video: video);
  }

  /// 입력칸 오른쪽 지우기 버튼.
  ///
  /// 키패드를 접든 펼치든 항상 자리에 있다. 지울 것이 없으면 흐리게 두어 눌러도
  /// 아무 일도 일어나지 않는다는 것을 보여 준다. 길게 누르면 전부 지운다.
  Widget _buildBackspaceButton() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _callee,
      builder: (context, value, _) {
        final hasText = value.text.isNotEmpty;
        return IconButton(
          tooltip: '지우기',
          onPressed: hasText
              ? () {
                  HapticFeedback.selectionClick();
                  _backspace();
                }
              : null,
          onLongPress: hasText
              ? () {
                  HapticFeedback.mediumImpact();
                  _clearCallee();
                }
              : null,
          icon: const Icon(Icons.backspace_outlined, size: 22),
          color: Colors.white54,
          disabledColor: Colors.white24,
        );
      },
    );
  }

  Future<void> _hangUpAndLeave() async {
    if (_leaving) return;
    _leaving = true;
    if (widget.service.hasCall) await widget.service.hangup();
    await widget.service.disconnect();
    if (mounted) Navigator.of(context).pop(DialerExit.userEnded);
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangUpAndLeave();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('GotDoor'),
          actions: [
            IconButton(
              tooltip: '단말 등록 상태',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DeviceRegistrationScreen(),
                ),
              ),
            ),
            IconButton(
              tooltip: '등록 해제',
              icon: const Icon(Icons.logout),
              onPressed: _hangUpAndLeave,
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: service,
          builder: (context, _) => AuroraBackground(
            // 통화 중에는 배경 연산을 멈춰 오디오 쪽에 자원을 넘긴다.
            animate: service.callState != CallState.active,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: switch (service.callState) {
                  CallState.none => _buildIdle(context),
                  CallState.incoming => _buildIncoming(context),
                  CallState.outgoing ||
                  CallState.ringing => _buildOutgoing(context),
                  CallState.active => _buildActive(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- 대기 화면

  Widget _buildIdle(BuildContext context) {
    final service = widget.service;
    final registered = service.isRegistered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusPill(
          tone: registered ? StatusTone.success : StatusTone.warning,
          icon: registered ? Icons.check_circle : Icons.sync,
          message: registered
              ? '내선 ${service.extension} 등록됨 · ${SipConfig.domain}'
              : 'SIP 등록 대기 중',
        ),
        Expanded(child: _centered([
          // 키패드를 펼치면 마크가 자리를 내준다. 둘 다 넣으면 화면을 넘친다.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _keypadOpen
                ? const SizedBox(width: double.infinity, height: 8)
                : const Padding(
                    padding: EdgeInsets.only(bottom: 28),
                    child: Center(child: JanusMark(width: 150)),
                  ),
          ),
          GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: SectionLabel('상대 번호', icon: Icons.dialpad),
                  ),
                  IconButton(
                    tooltip: _keypadOpen ? '키패드 접기' : '키패드 펼치기',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _keypadOpen
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 20,
                      color: Colors.white54,
                    ),
                    onPressed: () =>
                        setState(() => _keypadOpen = !_keypadOpen),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _callee,
                keyboardType: TextInputType.text,
                autocorrect: false,
                textAlign: TextAlign.center,
                // 내선은 10자리다(동4+호4+순번2). 자간과 크기를 그 폭에 맞춘다.
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: widget.defaultCallee.isEmpty
                      ? '0101080500'
                      : widget.defaultCallee,
                  hintStyle: const TextStyle(
                    color: Colors.white24,
                    letterSpacing: 2,
                  ),
                  // 지우기는 키패드를 접어도 쓸 수 있어야 하므로 입력칸에 붙인다.
                  suffixIcon: _buildBackspaceButton(),
                  suffixIconConstraints: _affixSize,
                  // 오른쪽 버튼만큼 번호가 왼쪽으로 밀리지 않게 폭을 비워 둔다.
                  prefixIcon: const SizedBox.shrink(),
                  prefixIconConstraints: _affixSize,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '내선 번호 또는 sip: 로 시작하는 전체 URI',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _keypadOpen
                    ? Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: DialPad(onDigit: _appendDigit),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: GlowButton(
                  label: '음성 통화',
                  icon: Icons.call,
                  gradient: AppPalette.liveGradient,
                  onPressed: () => _dial(video: false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlowButton(
                  label: '영상 통화',
                  icon: Icons.videocam,
                  onPressed: () => _dial(video: true),
                ),
              ),
            ],
          ),
        ])),
        if (service.errorMessage != null) ...[
          StatusPill(
            tone: StatusTone.danger,
            icon: Icons.error_outline,
            message: service.errorMessage!,
          ),
          // 영구 거부된 권한은 앱 안에서 다시 물을 수 없다. 설정으로 보낸다.
          if (service.needsMicPermission) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('권한 설정 열기'),
              ),
            ),
          ],
        ],
      ],
    );
  }

  // -------------------------------------------------------------- 발신 중

  Widget _buildOutgoing(BuildContext context) {
    final ringing = widget.service.callState == CallState.ringing;
    return _buildCallLayout(
      context,
      title: widget.service.peer ?? '',
      subtitle: ringing ? '상대 단말이 울리는 중…' : '발신 중…',
      accent: AppPalette.cyan,
      actions: [
        CircleActionButton(
          onPressed: widget.service.hangup,
          color: AppPalette.danger,
          icon: Icons.call_end,
          label: '끊기',
        ),
      ],
    );
  }

  // -------------------------------------------------------------- 착신

  Widget _buildIncoming(BuildContext context) {
    final service = widget.service;
    final video = service.incomingHasVideo;
    return _buildCallLayout(
      context,
      title: service.peer ?? '',
      subtitle: video ? '걸려온 영상 통화' : '걸려온 전화',
      accent: AppPalette.pink,
      actions: [
        CircleActionButton(
          onPressed: () => service.declineCall(),
          color: AppPalette.danger,
          icon: Icons.call_end,
          label: '거절',
        ),
        // 상대가 영상을 실어 보냈을 때만 고를 수 있다. 음성으로 받으면 내
        // 카메라는 켜지 않되 상대 영상은 그대로 보인다.
        if (video)
          CircleActionButton(
            onPressed: () => service.acceptCall(video: false),
            color: AppPalette.cyan,
            filled: false,
            icon: Icons.call,
            label: '음성만',
          ),
        CircleActionButton(
          onPressed: () => service.acceptCall(),
          color: AppPalette.success,
          icon: video ? Icons.videocam : Icons.call,
          label: '받기',
        ),
      ],
    );
  }

  // -------------------------------------------------------------- 통화 중

  Widget _buildActive(BuildContext context) {
    final service = widget.service;
    final video = service.isVideoCall;
    // 영상 통화는 버튼이 여섯이라 한 줄에 다 넣으려면 작아야 한다.
    final size = video ? 54.0 : 66.0;
    return _buildCallLayout(
      context,
      title: service.peer ?? '',
      subtitle: _formatDuration(service.connectedAt),
      accent: AppPalette.success,
      connected: true,
      video: video,
      actions: [
        CircleActionButton(
          onPressed: () =>
              setState(() => _inCallKeypad = !_inCallKeypad),
          color: _inCallKeypad ? AppPalette.cyan : Colors.white70,
          filled: false,
          size: size,
          icon: Icons.dialpad,
          label: '키패드',
        ),
        CircleActionButton(
          onPressed: service.toggleMic,
          color: service.micMuted ? AppPalette.warning : AppPalette.cyan,
          filled: false,
          size: size,
          icon: service.micMuted ? Icons.mic_off : Icons.mic,
          label: service.micMuted ? '음소거 중' : '마이크',
        ),
        if (service.localVideo) ...[
          CircleActionButton(
            onPressed: service.toggleCamera,
            color: service.cameraOff ? AppPalette.warning : AppPalette.cyan,
            filled: false,
            size: size,
            icon: service.cameraOff ? Icons.videocam_off : Icons.videocam,
            label: service.cameraOff ? '카메라 꺼짐' : '카메라',
          ),
          CircleActionButton(
            onPressed: service.switchCamera,
            color: Colors.white70,
            filled: false,
            size: size,
            icon: Icons.cameraswitch_outlined,
            label: '전환',
          ),
        ],
        CircleActionButton(
          onPressed: service.toggleSpeaker,
          color: service.speakerOn ? AppPalette.cyan : Colors.white70,
          filled: false,
          size: size,
          icon: service.speakerOn ? Icons.volume_up : Icons.hearing,
          label: service.speakerOn ? '스피커' : '수화기',
        ),
        CircleActionButton(
          onPressed: service.hangup,
          color: AppPalette.danger,
          size: size,
          icon: Icons.call_end,
          label: '끊기',
        ),
      ],
    );
  }

  String _formatDuration(DateTime? since) {
    if (since == null) return '통화 중';
    final elapsed = DateTime.now().difference(since);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // -------------------------------------------------------------- 공통 레이아웃

  Widget _buildCallLayout(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Color accent,
    required List<Widget> actions,
    bool connected = false,
    bool video = false,
  }) {
    // 버튼이 많아지면 한 줄에 못 들어가는 폭이 있다. 넘치면 다음 줄로 흘린다.
    final actionBar = Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 12,
      children: actions,
    );

    if (video) {
      // 영상은 남는 자리를 전부 차지한다. 진단 카드 대신 코덱 한 줄만 아래에
      // 붙인다 — 영상이 안 보일 때 H.264 협상 여부가 첫 단서다.
      return Column(
        children: [
          Expanded(
            child: _buildVideoPane(context, title: title, subtitle: subtitle),
          ),
          const SizedBox(height: 12),
          if (_inCallKeypad)
            GlassCard(
              radius: 20,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: DialPad(onDigit: _appendDigit, keySize: 48),
            )
          else
            _buildVideoStrip(),
          const SizedBox(height: 16),
          actionBar,
          const SizedBox(height: 12),
        ],
      );
    }

    return Column(
      children: [
        // 통화가 붙으면 진단 카드에 줄이 늘어난다. Spacer 로만 짜면 그때
        // 화면을 넘치므로, 넘칠 때만 스크롤되게 두고 버튼은 아래에 고정한다.
        Expanded(child: _centered([
          PulseAvatar(color: accent, animate: !connected),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: connected ? 20 : 15,
              color: connected ? accent : Colors.white60,
              fontWeight: connected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: connected ? 1.5 : 0.2,
            ),
          ),
          const SizedBox(height: 28),
          // 통화 중 키패드를 펼치면 진단 카드 자리를 대신 쓴다. 둘 다 넣으면
          // 화면을 넘치고, 통화 중에 동시에 볼 이유도 없다.
          if (connected && _inCallKeypad)
            GlassCard(
              radius: 20,
              child: Column(
                children: [
                  const SectionLabel('DTMF', icon: Icons.dialpad),
                  const SizedBox(height: 16),
                  DialPad(onDigit: _appendDigit, keySize: 58),
                ],
              ),
            )
          else
            _buildDiagnostics(context),
        ])),
        const SizedBox(height: 20),
        actionBar,
        const SizedBox(height: 16),
      ],
    );
  }

  // -------------------------------------------------------------- 영상 화면

  /// 상대 영상을 크게, 내 카메라를 구석에 작게 겹친다.
  ///
  /// 상대가 영상 없이 받았으면(음성 answer) 원격 자리에 아바타를 두고 내
  /// 카메라만 보여 준다. 그 반대(내 카메라 없이 상대 영상만)도 있다 —
  /// 인터폰 카메라를 보는 경우다.
  Widget _buildVideoPane(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final service = widget.service;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0F22),
          border: Border.all(color: AppPalette.glassStroke),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (service.remoteVideo)
              RTCVideoView(
                service.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PulseAvatar(color: AppPalette.success, animate: false),
                    const SizedBox(height: 12),
                    Text(
                      service.localVideo ? '상대 영상 없음' : '영상 대기 중',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            // 상대 번호와 통화 시간. 영상 위에 얹히므로 어두운 띠를 깐다.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.success,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (service.localVideo)
              Positioned(
                right: 12,
                bottom: 12,
                width: 108,
                height: 144,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      border: Border.all(
                        color: AppPalette.cyan.withValues(alpha: 0.55),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: service.cameraOff
                        ? const Center(
                            child: Icon(Icons.videocam_off,
                                color: Colors.white54),
                          )
                        : RTCVideoView(
                            service.localRenderer,
                            mirror: true,
                            objectFit:
                                RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 영상 통화 중 진단 한 줄. 카드 전체를 넣을 자리가 없다.
  Widget _buildVideoStrip() {
    final d = widget.service.diagnostics;
    final audio = d.audioCodec == null
        ? '오디오 대기'
        : (d.isG711 ? d.audioCodec! : '${d.audioCodec!} (G.711 아님)');
    final video = d.videoCodec == null
        ? '영상 협상 안 됨'
        : (d.isH264 ? d.videoCodec! : '${d.videoCodec!} (H.264 아님)');
    final ok = d.isG711 && (d.videoCodec == null || d.isH264);
    return StatusPill(
      tone: ok ? StatusTone.success : StatusTone.warning,
      icon: Icons.insights_outlined,
      message:
          '$audio · $video · ↑${_kb(d.bytesSent + d.videoBytesSent)} '
          '↓${_kb(d.bytesReceived + d.videoBytesReceived)}',
    );
  }

  /// 자리가 남으면 가운데 정렬, 모자라면 스크롤. 어느 기기에서도 넘치지 않는다.
  Widget _centered(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          // 스크롤 안에서는 높이가 무한이라 가운데 정렬이 먹지 않는다.
          // IntrinsicHeight 로 실제 높이를 확정해 줘야 한다.
          child: IntrinsicHeight(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  /// 미디어가 실제로 흐르는지 보여 준다.
  ///
  /// "연결은 됐는데 소리가 안 난다" 를 가르는 데 필요한 값만 모았다. 코덱이
  /// 특히 중요하다 — 인터폰은 G.711 만 하므로 opus 로 협상되면 소리가 안 난다.
  Widget _buildDiagnostics(BuildContext context) {
    final d = widget.service.diagnostics;
    final iceLabel = switch (d.iceState) {
      // onIceConnectionState 가 안 오는 기기가 있어 후보쌍으로 보완한다.
      null => d.candidatePair != null ? '연결됨 (후보쌍)' : '대기',
      RTCIceConnectionState.RTCIceConnectionStateConnected => '연결됨',
      RTCIceConnectionState.RTCIceConnectionStateCompleted => '완료',
      RTCIceConnectionState.RTCIceConnectionStateChecking => '확인 중',
      RTCIceConnectionState.RTCIceConnectionStateFailed => '실패',
      RTCIceConnectionState.RTCIceConnectionStateDisconnected => '끊김',
      RTCIceConnectionState.RTCIceConnectionStateClosed => '닫힘',
      _ => '새 연결',
    };

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('미디어 상태', icon: Icons.insights_outlined),
          const SizedBox(height: 10),
          _diagRow('ICE', iceLabel, ok: d.iceConnected),
          if (d.audioCodec != null)
            _diagRow(
              '코덱',
              d.isG711 ? d.audioCodec! : '${d.audioCodec!}  ← G.711 이 아닙니다',
              ok: d.isG711,
            ),
          _diagRow(
            '송신',
            '${_kb(d.bytesSent)}  (${d.packetsSent} 패킷)',
            ok: d.sending,
          ),
          _diagRow(
            '수신',
            '${_kb(d.bytesReceived)}  (${d.packetsReceived} 패킷)',
            ok: d.receiving,
          ),
          // 바이트는 흐르는데 끊겨 들릴 때 여기가 원인을 가른다.
          if (d.lossPercent != null)
            _diagRow(
              '손실',
              '${d.lossPercent!.toStringAsFixed(1)} %',
              ok: d.lossPercent! < 5,
            ),
          if (d.rttMs != null)
            _diagRow('왕복', '${d.rttMs} ms', ok: d.rttMs! < 300),
          _diagRow('원격 트랙', d.remoteTrackArrived ? '수신됨' : '없음',
              ok: d.remoteTrackArrived),
          if (d.videoCodec != null)
            _diagRow(
              '영상',
              '${d.videoCodec}  ↑${_kb(d.videoBytesSent)} ↓${_kb(d.videoBytesReceived)}',
              ok: d.isH264,
            ),
          if (d.hasRemoteDescription)
            _diagRow(
              'SDP 방향',
              '로컬 ${d.localAudioDirection ?? '?'} → '
                  '원격 ${d.remoteAudioDirection ?? '?'}',
              ok: d.remoteWillSend,
            ),
          if (d.candidatePair != null)
            _diagRow('경로', d.candidatePair!, ok: true),
        ],
      ),
    );
  }

  Widget _diagRow(String label, String value, {required bool ok}) {
    final color = ok ? AppPalette.success : AppPalette.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 62,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  String _kb(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}
