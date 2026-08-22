import 'package:flutter/material.dart';

import '../services/echo_test_service.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';
import 'widgets/video_tile.dart';

/// EchoTest 화면. 내 카메라와 서버가 되돌려 준 영상을 나란히 보여준다.
///
/// 두 번째 타일에 영상이 뜨면 시그널링·인증서·API secret·ICE·카메라 권한이
/// 전 구간 정상이라는 뜻이다.
class EchoTestScreen extends StatefulWidget {
  const EchoTestScreen({
    super.key,
    required this.serverUrl,
    this.apiSecret,
  });

  final String serverUrl;
  final String? apiSecret;

  @override
  State<EchoTestScreen> createState() => _EchoTestScreenState();
}

class _EchoTestScreenState extends State<EchoTestScreen> {
  final EchoTestService _service = EchoTestService();

  @override
  void initState() {
    super.initState();
    _service.start(serverUrl: widget.serverUrl, apiSecret: widget.apiSecret);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _stop() async {
    await _service.stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stop();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: const Text('EchoTest')),
        body: AuroraBackground(
          child: SafeArea(
            child: ListenableBuilder(
              listenable: _service,
              builder: (context, _) => Column(
                children: [
                  Expanded(child: _buildBody(context)),
                  _buildControls(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_service.state == EchoTestState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48,
                  color: AppPalette.danger),
              const SizedBox(height: 16),
              Text(
                _service.errorMessage ?? '알 수 없는 오류가 발생했습니다',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(onPressed: _stop, child: const Text('돌아가기')),
            ],
          ),
        ),
      );
    }

    final local = _service.local;
    if (local == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          _buildStatusBanner(context),
          const SizedBox(height: 12),
          Expanded(child: VideoTile(participant: local)),
          const SizedBox(height: 12),
          Expanded(
            child: _service.echo == null
                ? _buildWaitingTile(context)
                : VideoTile(participant: _service.echo!),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    final (IconData icon, StatusTone tone, String label) = switch (
      _service.state
    ) {
      EchoTestState.idle => (Icons.circle_outlined, StatusTone.neutral, '대기 중'),
      EchoTestState.connecting => (Icons.sync, StatusTone.warning, '서버에 연결 중…'),
      EchoTestState.running when _service.isEchoing => (
        Icons.check_circle,
        StatusTone.success,
        '전 구간 정상 — 서버가 영상을 되돌려 주고 있습니다',
      ),
      EchoTestState.running => (
        Icons.hourglass_bottom,
        StatusTone.warning,
        '시그널링 완료 — 미디어 수신 대기 중',
      ),
      EchoTestState.error => (Icons.error, StatusTone.danger, '오류'),
    };

    return StatusPill(tone: tone, icon: icon, message: label);
  }

  Widget _buildWaitingTile(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text(
              '서버 반환 영상 대기 중',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: GlassCard(
        radius: 28,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CircleActionButton(
              size: 56,
              filled: false,
              onPressed: _service.toggleAudio,
              color: _service.audioEnabled
                  ? AppPalette.cyan
                  : AppPalette.warning,
              icon: _service.audioEnabled ? Icons.mic : Icons.mic_off,
              label: _service.audioEnabled ? '오디오 켬' : '오디오 끔',
            ),
            CircleActionButton(
              size: 56,
              filled: false,
              onPressed: _service.toggleVideo,
              color: _service.videoEnabled
                  ? AppPalette.cyan
                  : AppPalette.warning,
              icon: _service.videoEnabled ? Icons.videocam : Icons.videocam_off,
              label: _service.videoEnabled ? '비디오 켬' : '비디오 끔',
            ),
            CircleActionButton(
              size: 56,
              onPressed: _stop,
              color: AppPalette.danger,
              icon: Icons.stop,
              label: '중지',
            ),
          ],
        ),
      ),
    );
  }
}
