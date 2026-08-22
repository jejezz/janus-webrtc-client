import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_client/janus_client.dart';

import '../config/janus_config.dart';
import '../models/participant.dart';
import 'janus_connection.dart';

enum EchoTestState { idle, connecting, running, error }

/// janus.plugin.echotest 로 전 구간 배선을 검증한다.
///
/// 서버가 내 오디오/비디오를 그대로 되돌려 주므로, 화면에 원격 영상이 뜨면
/// 시그널링·인증서·API secret·ICE·카메라 권한이 전부 정상이라는 뜻이다.
/// 방이나 다른 참가자가 필요 없어 서버 상태와 무관하게 돌릴 수 있다.
///
/// [JanusEchoTestPlugin] 은 헬퍼 메서드가 없는 얇은 래퍼라 EchoTest 의 원본
/// 메시지 규약(`{audio, video, bitrate}`)을 [JanusPlugin.send] 로 직접 쓴다.
class EchoTestService extends ChangeNotifier {
  JanusConnection? _connection;
  JanusEchoTestPlugin? _plugin;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  EchoTestState _state = EchoTestState.idle;
  String? _errorMessage;
  bool _audioEnabled = true;
  bool _videoEnabled = true;

  /// 내 카메라 미리보기.
  Participant? _local;

  /// 서버가 되돌려 준 영상.
  Participant? _echo;

  EchoTestState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get audioEnabled => _audioEnabled;
  bool get videoEnabled => _videoEnabled;
  Participant? get local => _local;
  Participant? get echo => _echo;

  /// 서버가 실제로 미디어를 되돌려 주기 시작했는지.
  bool get isEchoing => _echo?.hasVideo ?? false;

  Future<void> start({
    required String serverUrl,
    String? apiSecret,
  }) async {
    if (_state == EchoTestState.connecting || _state == EchoTestState.running) {
      return;
    }
    _setState(EchoTestState.connecting);

    try {
      await _establish(serverUrl, apiSecret ?? '');
    } on JanusConnectionException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('EchoTest 시작에 실패했습니다: $e');
    }
  }

  static const Duration _connectTimeout = Duration(seconds: 20);

  Future<void> _establish(String serverUrl, String apiSecret) async {
    // create 가 거절되면 여기서 멈춘다. session_id 가 비어 있는 채로 attach 가
    // 나가지 않도록 단계마다 결과를 확인한다.
    final connection = await JanusConnection.open(
      serverUrl: serverUrl,
      apiSecret: apiSecret,
      refreshIntervalSeconds: 30,
      timeout: _connectTimeout,
    );
    _connection = connection;

    final plugin =
        await connection.attach<JanusEchoTestPlugin>(timeout: _connectTimeout);
    _plugin = plugin;

    _track<EventMessage>(plugin.messages, (payload) async {
      final event = JanusEvent.fromJson(payload.event);
      final data = event.plugindata?.data as Map<String, dynamic>?;

      // EchoTest 는 오류를 {"error_code":..,"error":".."} 로 돌려준다.
      if (data != null && data['error'] != null) {
        _fail('EchoTest 오류 ${data['error_code']}: ${data['error']}');
        return;
      }
      if (payload.jsep != null) {
        await plugin.handleRemoteJsep(payload.jsep);
        _setState(EchoTestState.running);
      }
    });

    _track<RemoteTrack>(plugin.remoteTrack, _onRemoteTrack);

    final local = Participant(id: 'local', isLocal: true, displayName: '내 카메라');
    await local.init();
    local.stream = await plugin.initializeMediaDevices(
      mediaConstraints: JanusConfig.localMediaConstraints,
    );
    local.renderer.srcObject = local.stream;
    local.hasVideo = local.stream?.getVideoTracks().isNotEmpty ?? false;
    _local = local;
    notifyListeners();

    // VideoRoom 의 publish 와 달리 되돌아오는 미디어를 받아야 하므로 recv 를 켠다.
    final offer = await plugin.createOffer(audioRecv: true, videoRecv: true);
    await plugin.send(
      data: {'audio': _audioEnabled, 'video': _videoEnabled},
      jsep: offer,
    );
  }

  Future<void> _onRemoteTrack(RemoteTrack event) async {
    final track = event.track;
    if (track == null) return;

    if (event.flowing != true) {
      if (track.kind == 'audio') {
        _echo?.audioMuted = true;
      } else if (track.kind == 'video') {
        _echo?.videoMuted = true;
      }
      notifyListeners();
      return;
    }

    var echo = _echo;
    if (echo == null) {
      echo = Participant(id: 'echo', isLocal: false, displayName: '서버 반환 영상');
      await echo.init();
      echo.stream = await createLocalMediaStream('echo');
      _echo = echo;
    }

    await echo.stream?.addTrack(track);
    echo.renderer.srcObject = echo.stream;
    if (track.kind == 'video') {
      echo.hasVideo = true;
      echo.videoMuted = false;
      echo.mid = event.mid;
    } else if (track.kind == 'audio') {
      echo.audioMuted = false;
      // 스피커로 그대로 나가면 하울링이 나므로 되돌아온 오디오는 음소거해 둔다.
      echo.renderer.muted = true;
    }
    notifyListeners();
  }

  /// EchoTest 는 `{"audio": false}` 로 해당 방향의 릴레이 자체를 멈춘다.
  Future<void> toggleAudio() async {
    _audioEnabled = !_audioEnabled;
    await _plugin?.send(data: {'audio': _audioEnabled});
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    _videoEnabled = !_videoEnabled;
    await _plugin?.send(data: {'video': _videoEnabled});
    notifyListeners();
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    await _local?.dispose();
    await _echo?.dispose();
    _local = null;
    _echo = null;

    try {
      await _plugin?.hangup();
      await _plugin?.dispose();
      _connection?.dispose();
    } catch (e) {
      debugPrint('stop() 중 정리 실패: $e');
    }

    _plugin = null;
    _connection = null;
    _audioEnabled = true;
    _videoEnabled = true;

    _setState(EchoTestState.idle);
  }

  void _track<T>(Stream<T>? stream, Future<void> Function(T event) handler) {
    if (stream == null) return;
    _subscriptions.add(stream.listen(
      (event) async {
        try {
          await handler(event);
        } catch (e) {
          debugPrint('EchoTest 이벤트 처리 실패: $e');
        }
      },
      onError: (Object e) => _fail('Janus 연결 오류: $e'),
    ));
  }

  void _setState(EchoTestState state) {
    if (_state == state) return;
    _state = state;
    if (state != EchoTestState.error) _errorMessage = null;
    notifyListeners();
  }

  void _fail(String message) {
    _errorMessage = message;
    _state = EchoTestState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
