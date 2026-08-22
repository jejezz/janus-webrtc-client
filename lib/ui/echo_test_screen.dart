import 'package:flutter/material.dart';

import '../services/echo_test_service.dart';
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
        appBar: AppBar(title: const Text('EchoTest')),
        body: ListenableBuilder(
          listenable: _service,
          builder: (context, _) => _buildBody(context),
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: _service,
          builder: (context, _) => _buildControls(context),
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
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
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
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          _buildStatusBanner(context),
          const SizedBox(height: 8),
          Expanded(child: VideoTile(participant: local)),
          const SizedBox(height: 8),
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
    final (IconData icon, Color color, String label) = switch (_service.state) {
      EchoTestState.idle => (Icons.circle_outlined, Colors.white38, '대기 중'),
      EchoTestState.connecting => (Icons.sync, Colors.amber, '서버에 연결 중…'),
      EchoTestState.running when _service.isEchoing => (
          Icons.check_circle,
          Colors.greenAccent,
          '전 구간 정상 — 서버가 영상을 되돌려 주고 있습니다',
        ),
      EchoTestState.running => (
          Icons.hourglass_bottom,
          Colors.amber,
          '시그널링 완료 — 미디어 수신 대기 중',
        ),
      EchoTestState.error => (Icons.error, Colors.redAccent, '오류'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingTile(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton.filledTonal(
              onPressed: _service.toggleAudio,
              icon: Icon(_service.audioEnabled ? Icons.mic : Icons.mic_off),
              tooltip: _service.audioEnabled ? '오디오 릴레이 끄기' : '오디오 릴레이 켜기',
            ),
            IconButton.filledTonal(
              onPressed: _service.toggleVideo,
              icon: Icon(
                  _service.videoEnabled ? Icons.videocam : Icons.videocam_off),
              tooltip: _service.videoEnabled ? '비디오 릴레이 끄기' : '비디오 릴레이 켜기',
            ),
            IconButton.filled(
              onPressed: _stop,
              style: IconButton.styleFrom(backgroundColor: Colors.redAccent),
              icon: const Icon(Icons.stop),
              tooltip: '중지',
            ),
          ],
        ),
      ),
    );
  }
}
