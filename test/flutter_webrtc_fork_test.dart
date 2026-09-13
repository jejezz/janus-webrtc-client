import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('flutter_webrtc 포크', () {
    // 이것이 빠지면 Baseline·packetization-mode=0 으로 내미는 상대(월패드,
    // 공동현관기, pjsip)의 영상이 협상에서 거절된다. 빌드는 멀쩡히 되고 통화를
    // 해 봐야 알게 되므로 여기서 막는다 (pubspec.yaml 의 dependency_overrides).
    //
    // saturn-mobile-client-flutter 와 같은 포크·같은 커밋을 쓴다. pub 의
    // flutter_webrtc 에 같은 수정이 올라간 뒤에야 override 를 걷어낼 수 있고,
    // 그때는 이 테스트도 함께 지운다.

    /// 포크의 커밋. 바꿀 때는 그 커밋의 CustomVideoDecoderFactory 가
    /// `profileLevels` 를 읽는지 확인하고 바꾼다.
    const ref = 'e09b0d7e4c759d95a086cf2e33be84235985707e';

    test('pubspec 이 포크를 커밋으로 고정해 가리킨다', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('github.com/jejezz/flutter_webrtc'));
      expect(pubspec, contains(ref));
    });

    test('lock 이 같은 커밋을 물고 있다', () {
      // ref 를 브랜치로 적으면 브랜치가 움직인 날 resolved-ref 만 달라진다.
      final lock = File('pubspec.lock').readAsStringSync();
      expect(lock, contains('resolved-ref: $ref'),
          reason: 'pubspec 의 ref 와 lock 의 resolved-ref 가 어긋났다');
    });
  });
}
