import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_client/janus_client.dart';

/// 화면에 그려질 참가자 한 명(= VideoRoom feed 하나)의 렌더링 상태.
///
/// 로컬 참가자는 [isLocal] 이 true 이며, 이 경우 [stream] 의 수명은
/// JanusPlugin 이 관리하므로 여기서 트랙을 정리하지 않는다.
class Participant {
  Participant({
    required this.id,
    required this.isLocal,
    this.displayName,
  });

  /// 로컬은 [VideoRoomService.localId], 원격은 Janus feed id 문자열.
  final String id;
  final bool isLocal;

  String? displayName;

  /// 원격 참가자의 비디오 mid. 통계 조회나 simulcast 제어에 쓰인다.
  String? mid;

  final RTCVideoRenderer renderer = RTCVideoRenderer();
  MediaStream? stream;

  bool audioMuted = false;
  bool videoMuted = false;

  /// 아직 video 트랙이 붙지 않았다면 자리표시자를 그린다.
  bool hasVideo = false;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await renderer.initialize();
  }

  Future<void> dispose() async {
    renderer.srcObject = null;
    if (!isLocal) {
      await stopAllTracks(stream);
      await stream?.dispose();
    }
    if (_initialized) {
      await renderer.dispose();
    }
  }
}
