import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 통화 중 미디어가 실제로 흐르는지 보여 주는 관측값.
///
/// "연결은 됐는데 소리가 안 난다" 를 가르려면 세 가지를 봐야 한다.
/// - ICE 가 붙었는가 ([iceState])
/// - 내 RTP 가 나가는가 ([bytesSent])
/// - 상대 RTP 가 들어오는가 ([bytesReceived])
///
/// 그리고 [audioCodec] 이 결정적이다. 인터폰은 G.711 만 하므로 여기가 `opus` 로
/// 협상됐다면 소리는 절대 나지 않는다.
class CallDiagnostics {
  const CallDiagnostics({
    this.iceState,
    this.audioCodec,
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.remoteTrackArrived = false,
    this.lossPercent,
    this.rttMs,
    this.candidatePair,
    this.localAudioDirection,
    this.remoteAudioDirection,
    this.hasRemoteDescription = false,
  });

  final RTCIceConnectionState? iceState;

  /// 받은 것 대비 잃어버린 비율. 소리가 끊기는지 가른다 — 바이트는 흐르는데
  /// 끊겨 들린다면 여기가 올라가 있다.
  final double? lossPercent;

  /// 왕복 시간(ms). 지연이 체감될 때 근거가 된다.
  final int? rttMs;

  /// 협상된 오디오 코덱 (`audio/PCMU`, `audio/opus` 등).
  final String? audioCodec;

  final int bytesSent;
  final int bytesReceived;
  final int packetsSent;
  final int packetsReceived;

  /// 원격 오디오 트랙 이벤트를 받았는지.
  final bool remoteTrackArrived;

  /// 선택된 ICE 후보쌍 요약.
  final String? candidatePair;

  /// 내 offer 의 오디오 m-line 방향 (`sendrecv` / `sendonly` …).
  final String? localAudioDirection;

  /// 상대 answer 의 오디오 m-line 방향.
  ///
  /// 여기가 `recvonly` 나 `inactive` 면 상대는 우리에게 아무것도 보내지 않겠다고
  /// 답한 것이다. 그러면 원격 트랙도 안 생기고 수신도 0 이 된다.
  final String? remoteAudioDirection;

  /// 원격 SDP 가 적용됐는지.
  final bool hasRemoteDescription;

  /// ICE 가 붙었는지.
  ///
  /// flutter_webrtc 의 `onIceConnectionState` 는 기기에 따라 안 올 때가 있어,
  /// nominated 된 후보쌍이 잡혔으면 붙은 것으로 본다.
  bool get iceConnected =>
      candidatePair != null ||
      iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
      iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted;

  /// 상대가 우리에게 미디어를 보내겠다고 답했는지.
  bool get remoteWillSend {
    final direction = remoteAudioDirection;
    if (direction == null) return !hasRemoteDescription ? false : true;
    return direction == 'sendrecv' || direction == 'sendonly';
  }

  bool get sending => bytesSent > 0;
  bool get receiving => bytesReceived > 0;

  /// 양방향 RTP 가 확인된 상태.
  bool get mediaFlowing => sending && receiving;

  /// 코덱이 G.711 로 협상됐는지. 인터폰과 붙으려면 반드시 참이어야 한다.
  bool get isG711 {
    final codec = audioCodec?.toLowerCase();
    if (codec == null) return false;
    return codec.contains('pcmu') || codec.contains('pcma');
  }

  CallDiagnostics copyWith({
    RTCIceConnectionState? iceState,
    String? audioCodec,
    int? bytesSent,
    int? bytesReceived,
    int? packetsSent,
    int? packetsReceived,
    bool? remoteTrackArrived,
    double? lossPercent,
    int? rttMs,
    String? candidatePair,
    String? localAudioDirection,
    String? remoteAudioDirection,
    bool? hasRemoteDescription,
  }) {
    return CallDiagnostics(
      iceState: iceState ?? this.iceState,
      audioCodec: audioCodec ?? this.audioCodec,
      bytesSent: bytesSent ?? this.bytesSent,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      packetsSent: packetsSent ?? this.packetsSent,
      packetsReceived: packetsReceived ?? this.packetsReceived,
      remoteTrackArrived: remoteTrackArrived ?? this.remoteTrackArrived,
      lossPercent: lossPercent ?? this.lossPercent,
      rttMs: rttMs ?? this.rttMs,
      candidatePair: candidatePair ?? this.candidatePair,
      localAudioDirection: localAudioDirection ?? this.localAudioDirection,
      remoteAudioDirection: remoteAudioDirection ?? this.remoteAudioDirection,
      hasRemoteDescription: hasRemoteDescription ?? this.hasRemoteDescription,
    );
  }

  /// SDP 의 오디오 m-section 에서 방향 속성을 뽑는다.
  ///
  /// 방향이 세션 레벨에만 있거나 아예 없으면 규격상 기본값은 `sendrecv` 다.
  static String? audioDirectionOf(String? sdp) {
    if (sdp == null) return null;
    const directions = {'sendrecv', 'sendonly', 'recvonly', 'inactive'};

    String? sessionLevel;
    String? mediaLevel;
    var inAudio = false;
    var seenMedia = false;

    for (final raw in const LineSplitter().convert(sdp)) {
      final line = raw.trim();
      if (line.startsWith('m=')) {
        seenMedia = true;
        inAudio = line.startsWith('m=audio');
        continue;
      }
      if (!line.startsWith('a=')) continue;
      final value = line.substring(2);
      if (!directions.contains(value)) continue;
      if (!seenMedia) {
        sessionLevel = value;
      } else if (inAudio) {
        mediaLevel = value;
      }
    }
    return mediaLevel ?? sessionLevel ?? (sdp.contains('m=audio') ? 'sendrecv' : null);
  }

  /// `getStats()` 결과에서 오디오 관련 값만 추려 낸다.
  static CallDiagnostics fromStats(
    List<StatsReport> reports, {
    RTCIceConnectionState? iceState,
    bool remoteTrackArrived = false,
    String? localSdp,
    String? remoteSdp,
  }) {
    var bytesSent = 0;
    var bytesReceived = 0;
    var packetsSent = 0;
    var packetsReceived = 0;
    String? codecId;
    String? codec;
    String? candidatePair;
    var packetsLost = 0;
    int? rttMs;

    final byId = {for (final report in reports) report.id: report};

    for (final report in reports) {
      final values = report.values;
      // 구현에 따라 'kind' 또는 'mediaType' 을 쓴다.
      final kind = values['kind'] ?? values['mediaType'];

      switch (report.type) {
        case 'outbound-rtp':
          if (kind != 'audio') continue;
          bytesSent += _asInt(values['bytesSent']);
          packetsSent += _asInt(values['packetsSent']);
          codecId ??= values['codecId'] as String?;
        case 'inbound-rtp':
          if (kind != 'audio') continue;
          bytesReceived += _asInt(values['bytesReceived']);
          packetsReceived += _asInt(values['packetsReceived']);
          packetsLost += _asInt(values['packetsLost']);
          codecId ??= values['codecId'] as String?;
        case 'remote-inbound-rtp':
          // 상대가 보고해 주는 값이다. 초 단위라 ms 로 바꾼다.
          final rtt = _asDouble(values['roundTripTime']);
          if (rtt != null) rttMs = (rtt * 1000).round();
          packetsLost += _asInt(values['packetsLost']);
        case 'candidate-pair':
          final nominated = values['nominated'] == true;
          final succeeded = values['state'] == 'succeeded';
          if (nominated && succeeded) {
            final local = byId[values['localCandidateId']]?.values['candidateType'];
            final remote =
                byId[values['remoteCandidateId']]?.values['candidateType'];
            candidatePair = '$local → $remote';
            // 상대 보고가 없으면 후보쌍 값으로 대신한다.
            final rtt = _asDouble(values['currentRoundTripTime']);
            if (rttMs == null && rtt != null) rttMs = (rtt * 1000).round();
          }
      }
    }

    if (codecId != null) {
      codec = byId[codecId]?.values['mimeType'] as String?;
    }

    return CallDiagnostics(
      iceState: iceState,
      audioCodec: codec,
      bytesSent: bytesSent,
      bytesReceived: bytesReceived,
      packetsSent: packetsSent,
      packetsReceived: packetsReceived,
      remoteTrackArrived: remoteTrackArrived,
      lossPercent: packetsReceived + packetsLost == 0
          ? null
          : packetsLost * 100 / (packetsReceived + packetsLost),
      rttMs: rttMs,
      candidatePair: candidatePair,
      localAudioDirection: audioDirectionOf(localSdp),
      remoteAudioDirection: audioDirectionOf(remoteSdp),
      hasRemoteDescription: remoteSdp != null,
    );
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
