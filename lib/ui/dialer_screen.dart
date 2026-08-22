import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/sip_config.dart';
import '../services/sip_service.dart';
import 'device_registration_screen.dart';

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
        body: SafeArea(
          child: ListenableBuilder(
            listenable: service,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: switch (service.callState) {
                CallState.none => _buildIdle(context),
                CallState.incoming => _buildIncoming(context),
                CallState.outgoing ||
                CallState.ringing =>
                  _buildOutgoing(context),
                CallState.active => _buildActive(context),
              },
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- 대기 화면

  Widget _buildIdle(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRegistrationBadge(context),
        const Spacer(),
        TextField(
          controller: _callee,
          keyboardType: TextInputType.text,
          autocorrect: false,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 2),
          decoration: const InputDecoration(
            labelText: '상대 번호',
            helperText: '내선 번호 또는 sip: 로 시작하는 전체 URI',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () {
            final target = _callee.text.trim();
            if (target.isEmpty) return;
            FocusScope.of(context).unfocus();
            widget.service.call(target);
          },
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          icon: const Icon(Icons.call),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('전화 걸기', style: TextStyle(fontSize: 16)),
          ),
        ),
        const Spacer(),
        if (widget.service.errorMessage != null)
          Text(
            widget.service.errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
      ],
    );
  }

  Widget _buildRegistrationBadge(BuildContext context) {
    final service = widget.service;
    final registered = service.isRegistered;
    final color = registered ? Colors.greenAccent : Colors.amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(registered ? Icons.check_circle : Icons.sync, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              registered
                  ? '내선 ${service.extension} 등록됨 · ${SipConfig.domain}'
                  : 'SIP 등록 대기 중',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- 발신 중

  Widget _buildOutgoing(BuildContext context) {
    final ringing = widget.service.callState == CallState.ringing;
    return _buildCallLayout(
      context,
      title: widget.service.peer ?? '',
      subtitle: ringing ? '상대 단말이 울리는 중…' : '발신 중…',
      actions: [
        _circleButton(
          onPressed: widget.service.hangup,
          color: Colors.redAccent,
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
      actions: [
        _circleButton(
          onPressed: () => widget.service.declineCall(),
          color: Colors.redAccent,
          icon: Icons.call_end,
          label: '거절',
        ),
        _circleButton(
          onPressed: widget.service.acceptCall,
          color: Colors.green,
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
      actions: [
        _circleButton(
          onPressed: service.toggleMic,
          color: service.micMuted ? Colors.orange : Colors.blueGrey,
          icon: service.micMuted ? Icons.mic_off : Icons.mic,
          label: service.micMuted ? '음소거 중' : '마이크',
        ),
        _circleButton(
          onPressed: service.toggleSpeaker,
          color: service.speakerOn ? Colors.blue : Colors.blueGrey,
          icon: service.speakerOn ? Icons.volume_up : Icons.hearing,
          label: service.speakerOn ? '스피커' : '수화기',
        ),
        _circleButton(
          onPressed: service.hangup,
          color: Colors.redAccent,
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
    required List<Widget> actions,
  }) {
    return Column(
      children: [
        const Spacer(),
        const CircleAvatar(radius: 44, child: Icon(Icons.doorbell, size: 40)),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(fontSize: 15, color: Colors.white60)),
        const Spacer(),
        _buildDiagnostics(context),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: actions,
        ),
        const SizedBox(height: 24),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    final color = ok ? Colors.greenAccent : Colors.orangeAccent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.remove_circle_outline,
              size: 14, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
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

  Widget _circleButton({
    required VoidCallback onPressed,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: Icon(icon, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
