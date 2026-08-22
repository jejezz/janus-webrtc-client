import 'package:flutter_test/flutter_test.dart';
import 'package:janus_client_app/models/call_diagnostics.dart';

const _sendrecv = '''
v=0
o=- 1 1 IN IP4 127.0.0.1
s=-
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 0 8
a=rtpmap:0 PCMU/8000
a=sendrecv
''';

const _recvonly = '''
v=0
o=- 1 1 IN IP4 127.0.0.1
s=-
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 0 8
a=rtpmap:0 PCMU/8000
a=recvonly
''';

/// 방향 속성이 없으면 규격상 기본값은 sendrecv 다.
const _noDirection = '''
v=0
o=- 1 1 IN IP4 127.0.0.1
s=-
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 0 8
a=rtpmap:0 PCMU/8000
''';

/// 비디오 m-section 의 방향에 헷갈리면 안 된다.
const _audioAfterVideo = '''
v=0
o=- 1 1 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=inactive
m=audio 9 UDP/TLS/RTP/SAVPF 0
a=sendonly
''';

void main() {
  group('audioDirectionOf', () {
    test('오디오 m-section 의 방향을 읽는다', () {
      expect(CallDiagnostics.audioDirectionOf(_sendrecv), 'sendrecv');
      expect(CallDiagnostics.audioDirectionOf(_recvonly), 'recvonly');
    });

    test('방향이 없으면 sendrecv 로 본다', () {
      expect(CallDiagnostics.audioDirectionOf(_noDirection), 'sendrecv');
    });

    test('다른 m-section 의 방향을 가져오지 않는다', () {
      expect(CallDiagnostics.audioDirectionOf(_audioAfterVideo), 'sendonly');
    });

    test('SDP 가 없으면 null', () {
      expect(CallDiagnostics.audioDirectionOf(null), isNull);
    });
  });

  group('remoteWillSend', () {
    test('원격이 recvonly 면 우리에게 미디어가 오지 않는다', () {
      const d = CallDiagnostics(
        hasRemoteDescription: true,
        remoteAudioDirection: 'recvonly',
      );
      expect(d.remoteWillSend, isFalse);
    });

    test('원격이 sendrecv 면 온다', () {
      const d = CallDiagnostics(
        hasRemoteDescription: true,
        remoteAudioDirection: 'sendrecv',
      );
      expect(d.remoteWillSend, isTrue);
    });
  });

  group('isG711', () {
    test('PCMU/PCMA 만 참', () {
      expect(const CallDiagnostics(audioCodec: 'audio/PCMU').isG711, isTrue);
      expect(const CallDiagnostics(audioCodec: 'audio/PCMA').isG711, isTrue);
      expect(const CallDiagnostics(audioCodec: 'audio/opus').isG711, isFalse);
      expect(const CallDiagnostics().isG711, isFalse);
    });
  });

  group('iceConnected', () {
    test('후보쌍이 잡혔으면 콜백이 없어도 붙은 것으로 본다', () {
      const d = CallDiagnostics(candidatePair: 'prflx → host');
      expect(d.iceConnected, isTrue);
    });
  });
}
