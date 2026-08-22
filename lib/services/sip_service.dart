import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_client/janus_client.dart';
import '../config/sip_config.dart';
import '../models/call_diagnostics.dart';
import 'janus_connection.dart';

/// 사용자에게 그대로 보여줄 메시지를 담은 내부 실패 신호.
class _SipFailure implements Exception {
  _SipFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// SIP 계정 등록 상태.
enum SipRegistrationState { idle, connecting, registering, registered, failed }

/// 통화 상태.
enum CallState {
  /// 통화 없음.
  none,

  /// 발신했고 아직 상대가 받지 않음.
  outgoing,

  /// 상대 단말이 울리는 중 (180/183).
  ringing,

  /// 착신이 들어와 사용자의 응답을 기다림.
  incoming,

  /// 통화 연결됨.
  active,
}

/// janus.plugin.sip 로 인터폰과 1:1 통화한다.
///
/// 앱은 SIP 를 직접 말하지 않는다. Janus 가 앱을 대신해 SIP 를 쓰고, 앱은 Janus
/// 와 WebSocket JSON 만 주고받는다. 방(VideoRoom) 개념은 없다.
///
/// 순서가 중요하다. 세션 → 핸들 → **SIP 등록** → 발신. 등록이 끝나기 전에 `call`
/// 을 보내면 실패한다.
class SipService extends ChangeNotifier {
  JanusConnection? _connection;
  JanusSipPlugin? _sip;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  SipRegistrationState _registrationState = SipRegistrationState.idle;
  CallState _callState = CallState.none;
  String? _errorMessage;

  String? _extension;
  String? _peer;
  String? _lastCallId;

  MediaStream? _localStream;

  /// 착신 이벤트로 받은 offer. 사용자가 받기를 누를 때 소비한다.
  RTCSessionDescription? _pendingOffer;

  /// `register` 요청의 ack 가 아니라 실제 등록 결과 이벤트를 기다리는 데 쓴다.
  Completer<void>? _registration;

  bool _micMuted = false;
  bool _speakerOn = false;
  DateTime? _connectedAt;

  CallDiagnostics _diagnostics = const CallDiagnostics();
  RTCIceConnectionState? _iceState;
  bool _remoteTrackArrived = false;
  Timer? _statsTimer;

  SipRegistrationState get registrationState => _registrationState;
  CallState get callState => _callState;
  String? get errorMessage => _errorMessage;

  /// 등록된 내 내선 번호.
  String? get extension => _extension;

  /// 통화 상대 표시용 번호.
  String? get peer => _peer;

  /// 현재 통화의 SIP Call-ID. FCM 으로 받은 `callId` 와 맞춰 보는 데 쓴다.
  String? get callId => _lastCallId;

  bool get micMuted => _micMuted;
  bool get speakerOn => _speakerOn;
  bool get isRegistered => _registrationState == SipRegistrationState.registered;
  bool get hasCall => _callState != CallState.none;

  /// 통화가 연결된 시각. 통화 시간 표시에 쓴다.
  DateTime? get connectedAt => _connectedAt;

  /// 미디어가 실제로 흐르는지 보여 주는 관측값.
  CallDiagnostics get diagnostics => _diagnostics;

  // --------------------------------------------------------------- 연결·등록

  /// Janus 에 붙고 SIP 계정을 등록한다.
  Future<void> connectAndRegister({
    required String serverUrl,
    required String apiSecret,
    required String extension,
    required String password,
    String? displayName,
  }) async {
    if (_registrationState == SipRegistrationState.connecting ||
        _registrationState == SipRegistrationState.registering) {
      return;
    }
    _setRegistration(SipRegistrationState.connecting);

    try {
      _extension = extension.trim();
      await _establish(serverUrl, apiSecret, password, displayName);
    } on JanusConnectionException catch (e) {
      await _abandon();
      _fail(e.message);
    } on _SipFailure catch (e) {
      await _abandon();
      _fail(e.message);
    } catch (e) {
      await _abandon();
      _fail('등록에 실패했습니다: $e');
    }
  }

  /// 등록에 실패한 뒤 남은 세션을 닫는다.
  ///
  /// 그냥 두면 트랜스포트의 자동 재연결 루프와 keepalive 타이머가 계속 돌면서
  /// 처리되지 않는 예외를 던진다.
  Future<void> _abandon() async {
    _stopStatsPolling();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _registration = null;
    try {
      await _sip?.dispose();
      _connection?.dispose();
    } catch (e) {
      debugPrint('실패 후 정리 중 오류: $e');
    }
    _sip = null;
    _connection = null;
  }

  static const Duration _stageTimeout = Duration(seconds: 20);

  Future<void> _establish(
    String serverUrl,
    String apiSecret,
    String password,
    String? displayName,
  ) async {
    // 각 단계가 실제로 성공했는지 확인한다. create 가 거절되면 여기서 멈추므로
    // session_id 가 비어 있는 채로 attach·message 가 나가지 않는다.
    final connection = await JanusConnection.open(
      serverUrl: serverUrl,
      apiSecret: apiSecret,
      // 세션 타임아웃이 60초라 기본값(50초)보다 짧게 잡는다.
      refreshIntervalSeconds: SipConfig.keepaliveIntervalSeconds,
      timeout: _stageTimeout,
    );
    _connection = connection;

    final sip = await connection.attach<JanusSipPlugin>(timeout: _stageTimeout);
    _sip = sip;
    _listen(sip);

    _setRegistration(SipRegistrationState.registering);
    final registration = Completer<void>();
    _registration = registration;

    await sip.register(
      SipConfig.toSipUri(_extension!),
      authuser: _extension,
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : _extension,
      secret: password,
      proxy: SipConfig.proxy,
      // 이 줄이 빠지면 INVITE 가 인터넷으로 새어 나가고 조용히 실패한다.
      outboundProxy: SipConfig.outboundProxy,
    );

    // register 요청은 ack 만 돌려준다. 실제 결과는 이벤트로 온다.
    await registration.future.timeout(
      _stageTimeout,
      onTimeout: () => throw _SipFailure(
        'SIP 등록 응답이 없습니다.\n'
        '내선 번호와 비밀번호, Kamailio 계정을 확인하세요.',
      ),
    );
  }

  void _listen(JanusSipPlugin sip) {
    // 원격 오디오 트랙이 실제로 도착했는지. 소리가 안 날 때 어디까지 갔는지
    // 가르는 첫 번째 단서다.
    _track<RemoteTrack>(sip.remoteTrack, (event) async {
      if (event.track?.kind != 'audio') return;
      _remoteTrackArrived = event.flowing == true;
      _diagnostics =
          _diagnostics.copyWith(remoteTrackArrived: _remoteTrackArrived);
      notifyListeners();
    });

    _hookPeerConnection(sip);

    // registration_failed 와 플러그인 오류는 타입 이벤트로 오지 않는다.
    // 원본 메시지에서 직접 읽지 않으면 등록 실패가 조용히 묻힌다.
    _track<EventMessage>(sip.messages, (payload) async {
      final data = JanusEvent.fromJson(payload.event).plugindata?.data;
      if (data is! Map) return;

      final error = data['error'];
      if (error != null) {
        _failRegistration('SIP 오류 ${data['error_code'] ?? ''}: $error'.trim());
        return;
      }
      final result = data['result'];
      if (result is Map && result['event'] == 'registration_failed') {
        _failRegistration(
          'SIP 등록이 거절되었습니다 (${result['code'] ?? '?'} ${result['reason'] ?? ''}).\n'
          '내선 번호와 비밀번호를 확인하세요.'
              .trim(),
        );
      }
    });

    _track<TypedEvent<JanusEvent>>(sip.typedMessages, (event) async {
      final data = event.event.plugindata?.data;

      if (data is SipRegisteredEvent) {
        if (_registration?.isCompleted == false) _registration!.complete();
        _setRegistration(SipRegistrationState.registered);
      } else if (data is SipUnRegisteredEvent) {
        _setRegistration(SipRegistrationState.idle);
      } else if (data is SipIncomingCallEvent) {
        // offer 는 사용자가 받기를 누를 때 소비한다.
        _pendingOffer = event.jsep;
        _peer = SipConfig.displayOf(data.result?.username);
        _lastCallId = data.callId;
        _setCall(CallState.incoming);
      } else if (data is SipCallingEvent) {
        _setCall(CallState.outgoing);
      } else if (data is SipRingingEvent) {
        _setCall(CallState.ringing);
      } else if (data is SipProgressEvent) {
        // 183 with SDP — 조기 미디어. answer 를 붙여 링백을 들려준다.
        await _applyAnswer(sip, event.jsep);
        _setCall(CallState.ringing);
      } else if (data is SipAcceptedEvent) {
        await _applyAnswer(sip, event.jsep);
        _connectedAt = DateTime.now();
        _startStatsPolling();
        _setCall(CallState.active);
      } else if (data is SipHangupEvent) {
        await _teardownCall();
      } else if (data is SipMissedCallEvent) {
        await _teardownCall();
      }
    });
  }

  /// 원격 answer 를 붙인다.
  ///
  /// 183(조기 미디어)로 answer 를 이미 받은 뒤에 200 OK 가 또 answer 를 실어
  /// 오는 경우가 있다. 그때 두 번째 `setRemoteDescription` 은 stable 상태에서
  /// 호출돼 예외가 되므로, local offer 가 걸려 있을 때만 적용한다.
  Future<void> _applyAnswer(
      JanusSipPlugin sip, RTCSessionDescription? jsep) async {
    if (jsep == null) return;
    final state = sip.webRTCHandle?.peerConnection?.signalingState;
    if (state != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      debugPrint('answer 무시 (signalingState=$state)');
      return;
    }
    await sip.handleRemoteJsep(jsep);
  }

  /// janus_client 가 쓰지 않는 콜백이라 그대로 가져다 쓴다.
  /// PeerConnection 을 새로 만들 때마다 다시 걸어야 한다.
  void _hookPeerConnection(JanusSipPlugin sip) {
    sip.webRTCHandle?.peerConnection?.onIceConnectionState = (state) {
      _iceState = state;
      _diagnostics = _diagnostics.copyWith(iceState: state);
      notifyListeners();
    };
  }

  /// 통화마다 PeerConnection 을 새로 만든다.
  ///
  /// `JanusPlugin.hangup()` 은 로컬 트랙만 stop 할 뿐 PeerConnection 을 닫지도
  /// 새로 만들지도 않는다. 그 상태로 다음 통화를 걸면 이전 통화의 remote
  /// description·DTLS·트랜시버가 남은 PC 위에서 재협상이 나가고, 새 SIP 세션을
  /// 여는 Janus 는 `a=inactive` 로 답한다. 그러면 원격 트랙이 안 생기고 수신이
  /// 0 이 된다 — 첫 통화만 되고 두 번째부터 한쪽만 들리는 증상이다.
  ///
  /// janus.js 와 마찬가지로 통화 직전에 스택을 새로 세운다.
  Future<void> _freshPeerConnection(JanusSipPlugin sip) async {
    final previous = sip.webRTCHandle?.peerConnection;
    if (previous != null) {
      try {
        await previous.close();
      } catch (e) {
        debugPrint('이전 PeerConnection 정리 실패: $e');
      }
    }
    // 새 PC 를 만들고 onTrack·onIceCandidate 를 다시 건다.
    await sip.initializeWebRTCStack();
    _hookPeerConnection(sip);
    _iceState = null;
    _remoteTrackArrived = false;
  }

  // --------------------------------------------------------------- 미디어 계측

  /// 통화 중 2초마다 RTP 통계를 읽어 미디어가 실제로 흐르는지 확인한다.
  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final pc = _sip?.webRTCHandle?.peerConnection;
      if (pc == null) return;
      try {
        final reports = await pc.getStats();
        final local = await pc.getLocalDescription();
        final remote = await pc.getRemoteDescription();
        _diagnostics = CallDiagnostics.fromStats(
          reports,
          iceState: _iceState,
          remoteTrackArrived: _remoteTrackArrived,
          localSdp: local?.sdp,
          remoteSdp: remote?.sdp,
        );
        _dumpSdpOnce(local?.sdp, remote?.sdp);
        notifyListeners();
      } catch (e) {
        debugPrint('getStats 실패: $e');
      }
    });
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _sdpDumped = false;
  }

  bool _sdpDumped = false;

  /// 통화당 한 번, 오디오 m-section 을 로그에 남긴다.
  ///
  /// 방향이나 코덱이 이상할 때 붙여 넣어 볼 수 있는 근거가 된다.
  void _dumpSdpOnce(String? localSdp, String? remoteSdp) {
    if (_sdpDumped || remoteSdp == null) return;
    _sdpDumped = true;
    debugPrint('=== 로컬 offer audio m-section ===\n${_audioSection(localSdp)}');
    debugPrint('=== 원격 answer audio m-section ===\n${_audioSection(remoteSdp)}');
  }

  String _audioSection(String? sdp) {
    if (sdp == null) return '(없음)';
    final lines = const LineSplitter().convert(sdp);
    final section = <String>[];
    var inAudio = false;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('m=')) {
        if (inAudio) break;
        inAudio = line.startsWith('m=audio');
      }
      if (inAudio) section.add(line);
    }
    return section.isEmpty ? '(m=audio 없음)' : section.join('\n');
  }

  // ------------------------------------------------------------------- 발신

  /// [target] 은 내선 번호(`0010200601`) 또는 전체 SIP URI 를 받는다.
  Future<void> call(String target) async {
    final sip = _sip;
    if (sip == null || !isRegistered) {
      _fail('먼저 SIP 등록을 마쳐야 합니다.');
      return;
    }
    if (hasCall) return;

    try {
      _peer = SipConfig.displayOf(SipConfig.toSipUri(target));
      _setCall(CallState.outgoing);

      // 이전 통화가 남긴 PeerConnection 위에서 재협상하지 않도록 새로 세운다.
      await _freshPeerConnection(sip);

      _localStream = await sip.initializeMediaDevices(
        mediaConstraints: SipConfig.callMediaConstraints,
      );
      _applyMicState();

      // offer 는 래퍼가 audioRecv 로 만든다. SDP 는 손대지 않는다 —
      // PCMU/PCMA 가 남아 있어야 인터폰과 소리가 통한다.
      await sip.call(SipConfig.toSipUri(target));
    } catch (e) {
      _fail('발신에 실패했습니다: $e');
      await _teardownCall();
    }
  }

  // ------------------------------------------------------------------- 착신

  /// 착신을 받는다. 로컬 미디어를 먼저 붙여야 answer 에 트랙이 실린다.
  Future<void> acceptCall() async {
    final sip = _sip;
    final offer = _pendingOffer;
    if (sip == null || offer == null) return;

    try {
      // 착신도 마찬가지다. 직전 통화의 PC 를 재사용하면 answer 가 어긋난다.
      await _freshPeerConnection(sip);

      _localStream = await sip.initializeMediaDevices(
        mediaConstraints: SipConfig.callMediaConstraints,
      );
      _applyMicState();

      // 트랙을 붙인 뒤에 remote offer 를 세팅해야 accept() 가 answer 를 만든다.
      await sip.handleRemoteJsep(offer);
      _pendingOffer = null;
      await sip.accept();

      _connectedAt = DateTime.now();
      _startStatsPolling();
      _setCall(CallState.active);
    } catch (e) {
      _fail('통화 수락에 실패했습니다: $e');
      await _teardownCall();
    }
  }

  /// 착신을 거절한다. 기본 486 Busy Here.
  Future<void> declineCall({int code = 486}) async {
    try {
      await _sip?.decline(code: code);
    } catch (e) {
      debugPrint('decline 실패: $e');
    }
    await _teardownCall();
  }

  // ------------------------------------------------------------------- 통화

  Future<void> hangup() async {
    try {
      await _sip?.hangup();
    } catch (e) {
      debugPrint('hangup 실패: $e');
    }
    await _teardownCall();
  }

  void toggleMic() {
    _micMuted = !_micMuted;
    _applyMicState();
    notifyListeners();
  }

  void _applyMicState() {
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !_micMuted;
    }
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (e) {
      debugPrint('스피커 전환 실패: $e');
    }
    notifyListeners();
  }

  Future<void> _teardownCall() async {
    _stopStatsPolling();
    _diagnostics = const CallDiagnostics();
    _iceState = null;
    _remoteTrackArrived = false;
    _pendingOffer = null;
    _peer = null;
    _lastCallId = null;
    _connectedAt = null;
    _micMuted = false;
    if (_speakerOn) {
      _speakerOn = false;
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (_) {
        // 통화가 이미 끝난 뒤라면 실패해도 무시한다.
      }
    }
    _localStream = null;
    _setCall(CallState.none);
  }

  // ----------------------------------------------------------------- 정리

  /// 등록을 해제하고 세션을 닫는다.
  Future<void> disconnect() async {
    _stopStatsPolling();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    try {
      if (isRegistered) await _sip?.unregister();
    } catch (e) {
      debugPrint('unregister 실패: $e');
    }
    try {
      await _sip?.dispose();
      _connection?.dispose();
    } catch (e) {
      debugPrint('세션 정리 실패: $e');
    }

    _sip = null;
    _connection = null;
    _extension = null;
    _localStream = null;
    _pendingOffer = null;
    _peer = null;
    _connectedAt = null;
    _callState = CallState.none;
    _setRegistration(SipRegistrationState.idle);
  }

  void _track<T>(Stream<T>? stream, Future<void> Function(T event) handler) {
    if (stream == null) return;
    _subscriptions.add(stream.listen(
      (event) async {
        try {
          await handler(event);
        } catch (e) {
          debugPrint('SIP 이벤트 처리 실패: $e');
        }
      },
      onError: (Object e) => _fail('Janus 연결 오류: $e'),
    ));
  }

  void _setRegistration(SipRegistrationState state) {
    if (_registrationState == state) return;
    _registrationState = state;
    if (state != SipRegistrationState.failed) _errorMessage = null;
    notifyListeners();
  }

  void _setCall(CallState state) {
    if (_callState == state) return;
    _callState = state;
    notifyListeners();
  }

  void _fail(String message) {
    _errorMessage = message;
    if (!isRegistered) _registrationState = SipRegistrationState.failed;
    notifyListeners();
  }

  /// 등록을 기다리는 쪽이 있으면 그쪽으로 실패를 넘긴다.
  void _failRegistration(String message) {
    final registration = _registration;
    if (registration != null && !registration.isCompleted) {
      registration.completeError(_SipFailure(message));
      return;
    }
    _fail(message);
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}
