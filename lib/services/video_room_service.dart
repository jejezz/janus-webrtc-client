import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_client/janus_client.dart';
import 'package:logging/logging.dart';

import '../config/janus_config.dart';
import '../models/participant.dart';

enum RoomConnectionState { idle, connecting, joined, error }

/// janus.plugin.videoroom 세션 하나를 통째로 감싼다.
///
/// Janus 의 multistream VideoRoom 은 핸들을 두 개 쓴다.
/// - publisher 핸들: 방에 join 하고 내 카메라를 publish 한다.
/// - subscriber 핸들: 다른 모든 참가자의 스트림을 하나의 PeerConnection 으로 받는다.
///
/// UI 는 [ChangeNotifier] 로 갱신되며, 이 클래스는 위젯을 전혀 알지 못한다.
class VideoRoomService extends ChangeNotifier {
  /// 로컬 참가자를 [participants] 에서 찾을 때 쓰는 키.
  static const String localId = 'local';

  JanusClient? _client;
  JanusTransport? _transport;
  JanusSession? _session;
  JanusVideoRoomPlugin? _publisher;
  JanusVideoRoomPlugin? _subscriber;

  final Map<String, Participant> _participants = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// feed id -> Janus 가 알려준 publisher 정보(`id`, `display`, `streams`).
  final Map<dynamic, Map<String, dynamic>> _publishersByFeedId = {};

  /// subscriber 핸들의 mid -> 스트림 정보(`feed_id`, `type` 등).
  final Map<String, dynamic> _streamInfoByMid = {};

  /// feed id -> { mid: 구독중 } . 중복 구독을 막는다.
  final Map<dynamic, Map<dynamic, bool>> _subscribedMidsByFeedId = {};

  RoomConnectionState _state = RoomConnectionState.idle;
  String? _errorMessage;
  bool _audioEnabled = true;
  bool _videoEnabled = true;

  dynamic _roomId;
  String? _pin;
  int? _myId;
  int? _myPrivateId;

  RoomConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get audioEnabled => _audioEnabled;
  bool get videoEnabled => _videoEnabled;

  /// 로컬 참가자가 항상 맨 앞에 오도록 정렬한 목록.
  List<Participant> get participants {
    final list = _participants.values.toList();
    list.sort((a, b) {
      if (a.isLocal == b.isLocal) return a.id.compareTo(b.id);
      return a.isLocal ? -1 : 1;
    });
    return list;
  }

  /// 방에 접속해 카메라를 publish 하기까지의 전체 흐름.
  Future<void> join({
    required String serverUrl,
    required String room,
    required String displayName,
    String? pin,
    String? apiSecret,
  }) async {
    if (_state == RoomConnectionState.connecting ||
        _state == RoomConnectionState.joined) {
      return;
    }
    _setState(RoomConnectionState.connecting);

    try {
      // 방 번호는 보통 정수지만 janus 가 stringIds 로 설정된 경우 문자열도 허용된다.
      _roomId = int.tryParse(room) ?? room;
      _pin = (pin == null || pin.isEmpty) ? null : pin;
      _myId = DateTime.now().millisecondsSinceEpoch;

      final secret = (apiSecret == null || apiSecret.isEmpty) ? null : apiSecret;
      // 스킴에 따라 WebSocket / REST 트랜스포트가 선택된다.
      _transport = JanusConfig.transportFor(serverUrl);
      _client = JanusClient(
        transport: _transport!,
        iceServers: JanusConfig.iceServers,
        isUnifiedPlan: true,
        // withCredentials 가 false 면 apiSecret 을 실어 보내지 않는다.
        withCredentials: secret != null,
        apiSecret: secret,
        loggerLevel: Level.INFO,
      );
      // WebSocket 핸드셰이크 실패(사설 CA 등)는 예외로 올라오지 않고 전송
      // 타임아웃으로만 드러난다. 자체 타임아웃을 걸어 UI 가 무한 대기하지 않게 한다.
      await _establish(displayName).timeout(_connectTimeout);
      // 실제 joined 상태 전환은 VideoRoomJoinedEvent 수신 시점에 일어난다.
    } on TimeoutException {
      _fail(
        '서버가 응답하지 않습니다.\n$serverUrl\n\n'
        '주소, TLS 인증서, API Secret 을 확인하세요.',
      );
    } catch (e) {
      _fail('방 접속에 실패했습니다: $e');
    }
  }

  static const Duration _connectTimeout = Duration(seconds: 20);

  Future<void> _establish(String displayName) async {
    _session = await _client!.createSession();
    await _attachPublisher();
    await _startLocalMedia(displayName);
    await _publisher!.joinPublisher(
      _roomId,
      displayName: displayName,
      id: _myId,
      pin: _pin,
    );
  }

  // ---------------------------------------------------------------- publisher

  Future<void> _attachPublisher() async {
    final publisher = await _session!.attach<JanusVideoRoomPlugin>();
    _publisher = publisher;

    _track<TypedEvent<JanusEvent>>(publisher.typedMessages, (event) async {
      final data = event.event.plugindata?.data;
      if (data is VideoRoomJoinedEvent) {
        _myPrivateId = data.privateId;
        // join 이 수락된 직후에만 publish 용 offer 를 만들 수 있다.
        final offer =
            await publisher.createOffer(audioRecv: false, videoRecv: false);
        await publisher.configure(bitrate: 0, sessionDescription: offer);
        _setState(RoomConnectionState.joined);
      } else if (data is VideoRoomLeavingEvent) {
        await _removeFeed(data.leaving);
      } else if (data is VideoRoomUnPublishedEvent) {
        await _removeFeed(data.unpublished);
      }
      await publisher.handleRemoteJsep(event.jsep);
    });

    // publishers 목록은 typed 이벤트에 담기지 않으므로 원본 메시지에서 읽는다.
    _track<EventMessage>(publisher.messages, (payload) async {
      final event = JanusEvent.fromJson(payload.event);
      await _onPublishers(
          event.plugindata?.data['publishers'] as List<dynamic>?);
    });

    _track<dynamic>(publisher.renegotiationNeeded, (_) async {
      final pc = publisher.webRTCHandle?.peerConnection;
      if (pc?.signalingState != RTCSignalingState.RTCSignalingStateStable) {
        return;
      }
      final offer =
          await publisher.createOffer(audioRecv: false, videoRecv: false);
      await publisher.configure(bitrate: 0, sessionDescription: offer);
    });
  }

  Future<void> _startLocalMedia(String displayName) async {
    final local =
        Participant(id: localId, isLocal: true, displayName: displayName);
    await local.init();
    local.stream = await _publisher!.initializeMediaDevices(
      mediaConstraints: JanusConfig.localMediaConstraints,
    );
    local.renderer.srcObject = local.stream;
    local.hasVideo = local.stream?.getVideoTracks().isNotEmpty ?? false;
    _participants[localId] = local;
    notifyListeners();
  }

  // --------------------------------------------------------------- subscriber

  /// 새로 등장한 publisher 들을 구독한다.
  ///
  /// 첫 호출에서는 subscriber 핸들을 새로 attach 하고, 이후에는 기존 구독에
  /// `update` 로 스트림만 덧붙인다.
  Future<void> _onPublishers(List<dynamic>? publishers) async {
    if (publishers == null || publishers.isEmpty) return;

    final List<PublisherStream> toSubscribe = [];
    for (final publisher in publishers.cast<Map>()) {
      final feedId = publisher['id'];
      if (feedId == null || feedId == _myId) continue;

      _publishersByFeedId[feedId] = {
        'id': feedId,
        'display': publisher['display'],
        'streams': publisher['streams'],
      };
      _participants[feedId.toString()]?.displayName =
          publisher['display'] as String?;

      for (final stream
          in (publisher['streams'] as List<dynamic>? ?? const []).cast<Map>()) {
        final mid = stream['mid'];
        if (mid == null || stream['disabled'] == true) continue;
        if (_subscribedMidsByFeedId[feedId]?[mid] == true) continue;

        (_subscribedMidsByFeedId[feedId] ??= {})[mid] = true;
        toSubscribe.add(PublisherStream(
          feed: feedId,
          mid: mid,
          simulcast: stream['simulcast'],
        ));
      }
    }
    if (toSubscribe.isEmpty) return;

    if (_subscriber == null) {
      await _attachSubscriber(toSubscribe);
    } else {
      await _subscriber!.update(
        subscribe: toSubscribe
            .map((e) => SubscriberUpdateStream(
                feed: e.feed, mid: e.mid, crossrefid: null))
            .toList(),
      );
    }
  }

  Future<void> _attachSubscriber(List<PublisherStream> streams) async {
    final subscriber = await _session!.attach<JanusVideoRoomPlugin>();
    _subscriber = subscriber;

    _track<EventMessage>(subscriber.messages, (payload) async {
      final event = JanusEvent.fromJson(payload.event);
      final streamList = event.plugindata?.data['streams'] as List<dynamic>?;
      for (final stream in streamList?.cast<Map>() ?? const <Map>[]) {
        _streamInfoByMid[stream['mid'].toString()] = stream;
      }
      if (payload.jsep != null) {
        await subscriber.handleRemoteJsep(payload.jsep);
        // start 는 answer 를 만들어 붙여 실제 수신을 개시한다.
        await subscriber.start(_roomId);
      }
    });

    _track<RemoteTrack>(subscriber.remoteTrack, _onRemoteTrack);

    await subscriber.joinSubscriber(
      _roomId,
      streams: streams,
      privateId: _myPrivateId,
      pin: _pin,
    );
  }

  Future<void> _onRemoteTrack(RemoteTrack event) async {
    final mid = event.mid;
    final track = event.track;
    if (mid == null || track == null) return;

    final feedId = _streamInfoByMid[mid.toString()]?['feed_id'];
    if (feedId == null) return;
    final key = feedId.toString();

    // flowing == false 는 상대가 해당 트랙을 껐다는 뜻이다.
    if (event.flowing != true) {
      _applyMute(key, track.kind, true);
      notifyListeners();
      return;
    }

    var participant = _participants[key];
    if (participant == null) {
      participant = Participant(
        id: key,
        isLocal: false,
        displayName: _publishersByFeedId[feedId]?['display'] as String?,
      );
      await participant.init();
      // 원격 트랙들을 담을 빈 컨테이너 스트림을 만들어 두고 하나씩 붙인다.
      participant.stream = await createLocalMediaStream('remote_$key');
      _participants[key] = participant;
    }

    await participant.stream?.addTrack(track);
    participant.renderer.srcObject = participant.stream;
    if (track.kind == 'video') {
      participant.hasVideo = true;
      participant.mid = mid;
    } else if (track.kind == 'audio') {
      participant.renderer.muted = false;
    }
    _applyMute(key, track.kind, false);
    notifyListeners();
  }

  void _applyMute(String key, String? kind, bool muted) {
    final participant = _participants[key];
    if (participant == null) return;
    if (kind == 'audio') {
      participant.audioMuted = muted;
    } else if (kind == 'video') {
      participant.videoMuted = muted;
    }
  }

  /// 나갔거나 unpublish 한 feed 를 화면과 구독 목록에서 제거한다.
  Future<void> _removeFeed(dynamic feedId) async {
    if (feedId == null) return;

    final info = _publishersByFeedId.remove(feedId);
    final participant = _participants.remove(feedId.toString());
    await participant?.dispose();

    final streams = (info?['streams'] as List<dynamic>?)?.cast<Map>();
    if (streams != null && streams.isNotEmpty && _subscriber != null) {
      await _subscriber!.update(
        unsubscribe: streams
            .map((s) => SubscriberUpdateStream(
                feed: feedId, mid: s['mid'], crossrefid: null))
            .toList(),
      );
    }

    _subscribedMidsByFeedId.remove(feedId);
    _streamInfoByMid.removeWhere((_, value) => value['feed_id'] == feedId);
    notifyListeners();
  }

  // ------------------------------------------------------------------- 조작

  Future<void> toggleAudio() async {
    _audioEnabled = !_audioEnabled;
    await _setSendEnabled('audio', _audioEnabled);
    _participants[localId]?.audioMuted = !_audioEnabled;
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    _videoEnabled = !_videoEnabled;
    await _setSendEnabled('video', _videoEnabled);
    _participants[localId]?.videoMuted = !_videoEnabled;
    notifyListeners();
  }

  /// transceiver 방향을 바꿔 송출을 멈춘다. Janus 가 다른 참가자에게 mute 사실을
  /// 전파해 주므로 트랙 자체를 끄는 것보다 낫다.
  Future<void> _setSendEnabled(String kind, bool enabled) async {
    final pc = _publisher?.webRTCHandle?.peerConnection;
    final transceivers = (await pc?.getTransceivers())
        ?.where((t) => t.sender.track?.kind == kind)
        .toList();
    if (transceivers == null || transceivers.isEmpty) return;
    await transceivers.first.setDirection(
      enabled ? TransceiverDirection.SendOnly : TransceiverDirection.Inactive,
    );
  }

  Future<void> switchCamera() async {
    final publisher = _publisher;
    if (publisher == null) return;
    await publisher.switchCamera();
    final local = _participants[localId];
    if (local != null) {
      local.stream = publisher.webRTCHandle?.localStream;
      local.renderer.srcObject = local.stream;
    }
    notifyListeners();
  }

  /// 방에서 나가고 모든 자원을 되돌린다. 실패해도 상태는 idle 로 되돌린다.
  Future<void> leave() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    for (final participant in _participants.values) {
      await participant.dispose();
    }
    _participants.clear();
    _publishersByFeedId.clear();
    _streamInfoByMid.clear();
    _subscribedMidsByFeedId.clear();

    try {
      await _subscriber?.hangup();
      await _publisher?.hangup();
      await _subscriber?.dispose();
      await _publisher?.dispose();
      // JanusSession.dispose() 는 동기 메서드다.
      _session?.dispose();
    } catch (e) {
      debugPrint('leave() 중 정리 실패: $e');
    }

    _subscriber = null;
    _publisher = null;
    _session = null;
    _client = null;
    _transport = null;
    _myId = null;
    _myPrivateId = null;
    _audioEnabled = true;
    _videoEnabled = true;

    _setState(RoomConnectionState.idle);
  }

  // ------------------------------------------------------------------- 내부

  /// 스트림 구독을 등록하고 [leave] 에서 일괄 취소할 수 있게 보관한다.
  void _track<T>(Stream<T>? stream, Future<void> Function(T event) handler) {
    if (stream == null) return;
    _subscriptions.add(stream.listen(
      (event) async {
        try {
          await handler(event);
        } catch (e) {
          debugPrint('Janus 이벤트 처리 실패: $e');
        }
      },
      onError: (Object e) => _fail('Janus 연결 오류: $e'),
    ));
  }

  void _setState(RoomConnectionState state) {
    if (_state == state) return;
    _state = state;
    if (state != RoomConnectionState.error) _errorMessage = null;
    notifyListeners();
  }

  void _fail(String message) {
    _errorMessage = message;
    _state = RoomConnectionState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(leave());
    super.dispose();
  }
}
