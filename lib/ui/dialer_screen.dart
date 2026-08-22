import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/sip_config.dart';
import '../services/sip_service.dart';
import 'device_registration_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';
import 'widgets/janus_mark.dart';
import 'widgets/pulse_avatar.dart';

/// 등록이 끝난 뒤의 화면. 발신과 착신 응답을 모두 여기서 처리한다.
class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key, required this.service});

  final SipService service;

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  late final TextEditingController _callee =
      TextEditingController(text: SipConfig.defaultCallee);

  /// 통화 시간 표시를 1초마다 갱신한다.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.service.callState == CallState.active) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _callee.dispose();
    super.dispose();
  }

  Future<void> _hangUpAndLeave() async {
    if (widget.service.hasCall) await widget.service.hangup();
    await widget.service.disconnect();
    if (mounted) Navigator.of(context).pop();
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
          title: const Text('인터폰 통화'),
          actions: [
            IconButton(
              tooltip: '착신용 단말 등록',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeviceRegistrationScreen(
                    defaultSipUser: service.extension,
                  ),
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
        const Spacer(),
        const Center(child: JanusMark(width: 150)),
        const SizedBox(height: 28),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('상대 번호', icon: Icons.dialpad),
              const SizedBox(height: 18),
              TextField(
                controller: _callee,
                keyboardType: TextInputType.text,
                autocorrect: false,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                ),
                decoration: const InputDecoration(
                  hintText: '1001',
                  hintStyle: TextStyle(color: Colors.white24, letterSpacing: 4),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '내선 번호 또는 sip: 로 시작하는 전체 URI',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        GlowButton(
          label: '전화 걸기',
          icon: Icons.call,
          gradient: AppPalette.liveGradient,
          onPressed: () {
            final target = _callee.text.trim();
            if (target.isEmpty) return;
            FocusScope.of(context).unfocus();
            widget.service.call(target);
          },
        ),
        const Spacer(),
        if (service.errorMessage != null)
          StatusPill(
            tone: StatusTone.danger,
            icon: Icons.error_outline,
            message: service.errorMessage!,
          ),
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
    return _buildCallLayout(
      context,
      title: widget.service.peer ?? '',
      subtitle: '걸려온 전화',
      accent: AppPalette.pink,
      actions: [
        CircleActionButton(
          onPressed: () => widget.service.declineCall(),
          color: AppPalette.danger,
          icon: Icons.call_end,
          label: '거절',
        ),
        CircleActionButton(
          onPressed: widget.service.acceptCall,
          color: AppPalette.success,
          icon: Icons.call,
          label: '받기',
        ),
      ],
    );
  }

  // -------------------------------------------------------------- 통화 중

  Widget _buildActive(BuildContext context) {
    final service = widget.service;
    return _buildCallLayout(
      context,
      title: service.peer ?? '',
      subtitle: _formatDuration(service.connectedAt),
      accent: AppPalette.success,
      connected: true,
      actions: [
        CircleActionButton(
          onPressed: service.toggleMic,
          color: service.micMuted ? AppPalette.warning : AppPalette.cyan,
          filled: false,
          icon: service.micMuted ? Icons.mic_off : Icons.mic,
          label: service.micMuted ? '음소거 중' : '마이크',
        ),
        CircleActionButton(
          onPressed: service.toggleSpeaker,
          color: service.speakerOn ? AppPalette.cyan : Colors.white70,
          filled: false,
          icon: service.speakerOn ? Icons.volume_up : Icons.hearing,
          label: service.speakerOn ? '스피커' : '수화기',
        ),
        CircleActionButton(
          onPressed: service.hangup,
          color: AppPalette.danger,
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
  }) {
    return Column(
      children: [
        const Spacer(),
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
        const Spacer(),
        _buildDiagnostics(context),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: actions.length == 1
              ? MainAxisAlignment.center
              : MainAxisAlignment.spaceEvenly,
          children: actions,
        ),
        const SizedBox(height: 16),
      ],
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
          _diagRow('원격 트랙', d.remoteTrackArrived ? '수신됨' : '없음',
              ok: d.remoteTrackArrived),
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
