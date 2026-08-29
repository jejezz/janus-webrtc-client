import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_client/janus_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/sip_config.dart';
import '../models/sip_account.dart';
import '../models/call_diagnostics.dart';
import 'call_foreground_service.dart';
import 'janus_connection.dart';
import 'push_service.dart';

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

  /// 지금 쓰고 있는 SIP 자격.
  SipAccount? _account;
  SipAccount? get account => _account;

  /// 마지막 등록 실패의 SIP 코드. 401 이면 비밀번호가 바뀐 것이므로
  /// `/register/mobile` 을 다시 불러 새 값을 받아야 한다.
  int? _registrationFailureCode;
  int? get registrationFailureCode => _registrationFailureCode;
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
  Timer? _errorTimer;

  /// 마이크 권한이 막혀 통화를 시작하지 못한 상태.
  ///
  /// 안드로이드는 권한이 없어도 통화 자체는 붙여 준다. 대신 녹음을 조용히
  /// 침묵 처리하므로(logcat: "App op 27 missing, silencing record") 상대에게는
  /// 아무 소리도 가지 않는다. 사용자는 "연결은 되는데 안 들린다" 로만 겪는다.
  bool _needsMicPermission = false;
  bool get needsMicPermission => _needsMicPermission;

  /// 이번 hangup 을 실패로 보면 안 되는지.
  ///
  /// 통화가 붙었거나 사용자가 직접 끊거나 거절한 경우다. 내가 끊으면
  /// `_teardownCall()` 이 먼저 돌아 통화 상태가 지워지고 **그 뒤에** Janus 의
  /// hangup 이벤트가 도착하므로, 통화 상태만 보면 정상 종료를 실패로 오인한다.
  /// 그래서 통화 밖에서도 값이 유지되는 별도 표시가 필요하다.
  bool _expectedHangup = false;

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
    required SipAccount account,
  }) async {
    if (_registrationState == SipRegistrationState.connecting ||
        _registrationState == SipRegistrationState.registering) {
      return;
    }
    _setRegistration(SipRegistrationState.connecting);
    _registrationFailureCode = null;

    try {
      _account = account;
      _extension = account.user;
      await _establish(serverUrl, apiSecret, account);
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
    SipAccount account,
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

    // username 과 authuser 를 같게 둔다. Kamailio 의
    // auth_check("$fd","subscriber","1") 이 "digest 사용자명 == To 사용자명" 을
    // 강제하므로, 다르면 401 이다 (client-migration.md).
    await sip.register(
      account.uri,
      authuser: account.user,
      displayName: account.user,
      secret: account.password,
      proxy: SipConfig.proxy,
      // 이 줄이 빠지면 INVITE 가 인터넷으로 새어 나가고 조용히 실패한다.
      outboundProxy: SipConfig.outboundProxy,
    );

    // register 요청은 ack 만 돌려준다. 실제 결과는 이벤트로 온다.
    await registration.future.timeout(
      _stageTimeout,
      onTimeout: () => throw _SipFailure(
        'SIP 등록 응답이 없습니다.\n'
        '배정된 번호(${account.user})의 Kamailio 계정을 확인하세요.',
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
      // 무엇이 실제로 오갔는지 남긴다. Janus 가 코드도 사유도 없이 끊을 때는
      // 원본 이벤트 말고는 단서가 없다.
      if (kDebugMode) {
        debugPrint('[sip] ${jsonEncode(payload.event)}'
            '${payload.jsep == null ? '' : ' (+jsep ${payload.jsep!.type})'}');
      }
      final data = JanusEvent.fromJson(payload.event).plugindata?.data;
      if (data is! Map) return;

      final error = data['error'];
      if (error != null) {
        _failRegistration('SIP 오류 ${data['error_code'] ?? ''}: $error'.trim());
        return;
      }
      final result = data['result'];
      if (result is Map && result['event'] == 'hangup') {
        // 패키지는 SipHangupEvent.fromJson(data) 로 만드는데 code/reason 은
        // data['result'] 안에 있어 늘 null 이 된다. 여기서 직접 읽는다.
        await _handleHangup(result['code'], result['reason']);
        return;
      }
      if (result is Map && result['event'] == 'registration_failed') {
        final code = result['code'];
        _registrationFailureCode = code is int ? code : null;
        _failRegistration(
          code == 401
              // 자리를 물려받은 단말이 생기면 비밀번호가 새로 발급된다.
              ? 'SIP 인증이 거절되었습니다 (401).\n서버에서 자격을 다시 받아 등록합니다.'
              : 'SIP 등록이 거절되었습니다 (${code ?? '?'} ${result['reason'] ?? ''}).'
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
        // 여기까지 왔다는 것은 앱이 깨어나 등록까지 마쳤다는 뜻이다.
        // 깨우기용 알림은 역할을 다했으므로 치운다.
        unawaited(PushService.dismissIncomingCall());
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
        _clearError();
        await _applyAnswer(sip, event.jsep);
        _connectedAt = DateTime.now();
        _expectedHangup = true;
        _startStatsPolling();
        _setCall(CallState.active);
      } else if (data is SipMissedCallEvent) {
        await _teardownCall();
      }
    });
  }

  /// 마이크를 쓸 수 있는지 확인한다. 없으면 통화를 시작하지 않는다.
  ///
  /// 한 번 영구 거부된 뒤에는 request() 가 대화상자를 띄우지 못하므로, 설정으로
  /// 보내는 것 말고는 방법이 없다.
  Future<bool> _ensureMicrophone() async {
    var status = await Permission.microphone.status;
    if (status.isDenied) status = await Permission.microphone.request();
    final granted = status.isGranted || status.isLimited;
    _needsMicPermission = !granted;
    if (!granted) {
      _fail(
        '마이크 권한이 없습니다.\n'
        '이대로 통화하면 상대에게 소리가 가지 않아 시작하지 않습니다.',
      );
    }
    return granted;
  }

  /// 통화가 끊겼을 때. 연결되기 전에 끊겼다면 그건 실패이므로 사유를 보여 준다.
  Future<void> _handleHangup(Object? code, Object? reason) async {
    final expected = _expectedHangup || _callState == CallState.active;
    debugPrint('SIP hangup: code=$code reason=$reason expected=$expected');
    await _teardownCall();
    if (expected) return;   // 정상적으로 통화하다 끝났거나 내가 끊은 것이다
    _fail(_hangupMessage(code, reason));
  }

  String _hangupMessage(Object? code, Object? reason) {
    final hint = switch (code) {
      486 => '상대가 통화 중입니다.\n앞선 통화가 상대 단말에 남아 있을 수 있습니다.',
      404 => '상대 내선을 찾을 수 없습니다.',
      480 => '상대가 지금 받을 수 없는 상태입니다.',
      408 => '상대가 응답하지 않았습니다.',
      403 => '서버가 발신을 거절했습니다.',
      488 => '미디어 협상에 실패했습니다. 코덱(G.711) 설정을 확인하세요.',
      _ => null,
    };
    final detail = [
      if (code != null) '$code',
      if (reason != null && '$reason'.trim().isNotEmpty) '$reason'.trim(),
    ].join(' ');

    if (hint != null) {
      return detail.isEmpty ? hint : '$hint ($detail)';
    }
    return detail.isEmpty
        ? '통화가 연결되지 않았습니다.'
        : '통화가 연결되지 않았습니다 ($detail).';
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
    _clearError();
    if (!await _ensureMicrophone()) return;
    _expectedHangup = false;

    try {
      _peer = SipConfig.displayOf(SipConfig.toSipUri(target, domain: _account?.domain));
      // 발신을 누른 순간부터 켠다. 상대가 받기 전에 홈으로 나가도 마이크가
      // 살아 있어야 연결되자마자 소리가 간다.
      await CallForegroundService.start(peer: _peer);
      _setCall(CallState.outgoing);

      // 이전 통화가 남긴 PeerConnection 위에서 재협상하지 않도록 새로 세운다.
      await _freshPeerConnection(sip);

      _localStream = await sip.initializeMediaDevices(
        mediaConstraints: SipConfig.callMediaConstraints,
      );
      _applyMicState();

      // offer 는 래퍼가 audioRecv 로 만든다. SDP 는 손대지 않는다 —
      // PCMU/PCMA 가 남아 있어야 인터폰과 소리가 통한다.
      await sip.call(SipConfig.toSipUri(target, domain: _account?.domain));
    } catch (e) {
      final reason = _describeSendFailure('발신에 실패했습니다', e);
      await _teardownCall();
      if (_linkIsDown(e)) {
        _dropLink();   // 등록 화면으로 돌려보내 다시 붙게 한다
      } else {
        _fail(reason);
      }
    }
  }

  // ------------------------------------------------------------------- 착신

  /// 착신을 받는다. 로컬 미디어를 먼저 붙여야 answer 에 트랙이 실린다.
  Future<void> acceptCall() async {
    final sip = _sip;
    final offer = _pendingOffer;
    if (sip == null || offer == null) return;
    _clearError();
    if (!await _ensureMicrophone()) return;
    _expectedHangup = false;

    try {
      await CallForegroundService.start(peer: _peer);
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
      _expectedHangup = true;
      _startStatsPolling();
      _setCall(CallState.active);
    } catch (e) {
      final reason = _describeSendFailure('통화 수락에 실패했습니다', e);
      await _teardownCall();
      if (_linkIsDown(e)) {
        _dropLink();
      } else {
        _fail(reason);
      }
    }
  }

  /// 착신을 거절한다. 기본 486 Busy Here.
  Future<void> declineCall({int code = 486}) async {
    _expectedHangup = true;
    try {
      await _sip?.decline(code: code);
    } catch (e) {
      debugPrint('decline 실패: $e');
    }
    await _teardownCall();
  }

  // ------------------------------------------------------------------- 통화

  Future<void> hangup() async {
    _expectedHangup = true;
    Object? failure;
    try {
      await _sip?.hangup();
    } catch (e) {
      // BYE 가 나가지 못하면 상대 단말은 계속 통화 중으로 남는다. 그러면
      // 다음 발신이 전부 486 으로 거절된다 — 조용히 넘기면 안 되는 실패다.
      debugPrint('hangup 실패: $e');
      failure = e;
    }
    await _teardownCall();
    if (failure != null) {
      _fail(
        '통화 종료를 서버에 전달하지 못했습니다.\n'
        '상대 단말이 통화 중으로 남아 다음 발신이 거절될 수 있습니다.\n'
        '${_describeSendFailure('원인', failure)}',
      );
    }
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
    await CallForegroundService.stop();
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
    _errorTimer?.cancel();
    _errorTimer = null;
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

  /// 소켓이 끊긴 것을 확인했을 때. 세션과 핸들도 서버에서 이미 무효라
  /// 재연결만으로는 못 살리고 재등록해야 한다.
  ///
  /// 죽은 트랜스포트를 그대로 두면 자동 재연결 루프가 계속 돌면서 처리되지 않는
  /// 예외를 던지고, 재등록 때마다 하나씩 쌓인다. 여기서 확실히 닫는다.
  void _dropLink() {
    _stopStatsPolling();
    _callState = CallState.none;
    _errorMessage = '서버와의 연결이 끊어졌습니다.\n다시 등록해야 통화할 수 있습니다.';
    _registrationState = SipRegistrationState.failed;
    notifyListeners();
    unawaited(_abandon());
  }

  /// janus_client 가 삼킨 전송 오류를 사람이 읽을 수 있는 문장으로 바꾼다.
  ///
  /// `JanusPlugin.send()` 는 예외를 로그로만 흘리고 null 을 돌려주는데, 그 null 이
  /// `JanusEvent.fromJson` 으로 들어가 `NoSuchMethodError: []("janus")` 로
  /// 둔갑한다. 진짜 이유는 로거가 잡아 둔 쪽에 있다.
  String _describeSendFailure(String prefix, Object error) {
    final swallowed = _connection?.lastSwallowedError;
    if (error is NoSuchMethodError && swallowed != null) {
      return '$prefix: $swallowed';
    }
    return '$prefix: $error';
  }

  /// 소켓이 죽어서 실패한 것인지.
  ///
  /// 미리 상태 플래그를 보고 막지는 않는다. WebRTC 가 ICE 때문에 네트워크를
  /// 새로 요청하는 순간 플래그가 잠깐 내려가는데, 그걸로 막으면 멀쩡한 통화가
  /// 시작도 못 한다. 실제로 보내 보고 실패한 뒤에만 판단한다.
  bool _linkIsDown(Object error) {
    final swallowed = _connection?.lastSwallowedError;
    return error is NoSuchMethodError &&
        swallowed != null &&
        swallowed.contains('WebSocket is not connected');
  }

  void _setCall(CallState state) {
    if (_callState == state) return;
    _callState = state;
    notifyListeners();
  }

  void _fail(String message) {
    _errorMessage = message;
    if (!isRegistered) _registrationState = SipRegistrationState.failed;
    _scheduleErrorClear();
    notifyListeners();
  }

  /// 통화 단계의 실패 문구는 잠시 뒤 스스로 사라진다.
  ///
  /// 등록 실패는 사용자가 설정을 고쳐야 풀리므로 남겨 둔다. 반면 발신 실패는
  /// 다음 통화가 멀쩡히 붙어도 화면에 계속 붙어 있으면 거짓말이 된다.
  static const Duration _errorLifetime = Duration(seconds: 8);

  void _scheduleErrorClear() {
    _errorTimer?.cancel();
    _errorTimer = null;
    if (!isRegistered) return;
    _errorTimer = Timer(_errorLifetime, () {
      _errorTimer = null;
      if (_errorMessage == null) return;
      _errorMessage = null;
      notifyListeners();
    });
  }

  /// 새 시도를 시작할 때 지난 실패를 지운다.
  void _clearError() {
    _errorTimer?.cancel();
    _errorTimer = null;
    if (_errorMessage == null) return;
    _errorMessage = null;
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
