import 'package:flutter/material.dart';

import '../services/video_room_service.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';
import 'widgets/video_tile.dart';

/// 방에 접속한 뒤의 화면. [VideoRoomService] 의 수명을 소유한다.
class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.serverUrl,
    required this.room,
    required this.displayName,
    this.pin,
    this.apiSecret,
  });

  final String serverUrl;
  final String room;
  final String displayName;
  final String? pin;
  final String? apiSecret;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final VideoRoomService _service = VideoRoomService();

  @override
  void initState() {
    super.initState();
    _service.join(
      serverUrl: widget.serverUrl,
      room: widget.room,
      displayName: widget.displayName,
      pin: widget.pin,
      apiSecret: widget.apiSecret,
    );
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    await _service.leave();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text('방 ${widget.room}'),
          actions: [
            IconButton(
              onPressed: _service.switchCamera,
              icon: const Icon(Icons.cameraswitch),
              tooltip: '카메라 전환',
            ),
          ],
        ),
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
    switch (_service.state) {
      case RoomConnectionState.error:
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
                OutlinedButton(onPressed: _leave, child: const Text('돌아가기')),
              ],
            ),
          ),
        );
      case RoomConnectionState.idle:
      case RoomConnectionState.connecting:
        if (_service.participants.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        break;
      case RoomConnectionState.joined:
        break;
    }

    final participants = _service.participants;
    if (participants.isEmpty) {
      return const Center(child: Text('참가자가 없습니다'));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: participants.length == 1 ? 1 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 3 / 4,
        ),
        itemCount: participants.length,
        itemBuilder: (context, index) => VideoTile(
          key: ValueKey(participants[index].id),
          participant: participants[index],
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
              label: _service.audioEnabled ? '마이크' : '음소거',
            ),
            CircleActionButton(
              size: 56,
              filled: false,
              onPressed: _service.toggleVideo,
              color: _service.videoEnabled
                  ? AppPalette.cyan
                  : AppPalette.warning,
              icon: _service.videoEnabled ? Icons.videocam : Icons.videocam_off,
              label: _service.videoEnabled ? '카메라' : '꺼짐',
            ),
            CircleActionButton(
              size: 56,
              onPressed: _leave,
              color: AppPalette.danger,
              icon: Icons.call_end,
              label: '나가기',
            ),
          ],
        ),
      ),
    );
  }
}
