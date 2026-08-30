import 'package:flutter_test/flutter_test.dart';
import 'package:janus_client_app/config/sip_config.dart';
import 'package:janus_client_app/models/sip_account.dart';
import 'package:janus_client_app/services/credential_store.dart';

void main() {
  group('SipConfig', () {
    test('내선 번호를 SIP URI 로 정규화한다', () {
      expect(SipConfig.toSipUri('1001'), 'sip:1001@${SipConfig.domain}');
      expect(SipConfig.toSipUri(' 0010200601 '),
          'sip:0010200601@${SipConfig.domain}');
    });

    test('이미 URI 면 그대로 둔다', () {
      expect(SipConfig.toSipUri('sip:1001@other.test'), 'sip:1001@other.test');
      expect(SipConfig.toSipUri('sips:1001@other.test'), 'sips:1001@other.test');
    });

    test('URI 에서 표시용 번호만 뽑는다', () {
      expect(SipConfig.displayOf('sip:0010200601@pluto.org'), '0010200601');
      expect(SipConfig.displayOf(null), '알 수 없음');
    });

    test('시그널링 주소에서 rtc-relay 주소를 만든다 — /mobile 이 붙어야 한다', () {
      expect(
        SipConfig.deviceRegistrationUrl(
            signalingUrl: 'wss://example.test:28443/janus-ws'),
        'https://example.test:28443/relay/register/mobile',
      );
      expect(
        SipConfig.deviceRegistrationUrl(
            signalingUrl: 'ws://192.168.0.9:8188/janus-ws'),
        'http://192.168.0.9:8188/relay/register/mobile',
      );
    });
  });

  group('SipAccount', () {
    test('등록 응답의 sip 를 읽는다', () {
      final account = SipAccount.fromJson({
        'user': '0101080501',
        'domain': 'pluto.org',
        'password': '9e807d',
      });
      expect(account, isNotNull);
      expect(account!.uri, 'sip:0101080501@pluto.org');
    });

    test('sip 가 없거나 비면 null 이다 — 번호가 배정되지 않은 세대다', () {
      expect(SipAccount.fromJson(null), isNull);
      expect(SipAccount.fromJson(const {}), isNull);
      expect(
        SipAccount.fromJson(const {'user': '0101080501', 'domain': 'pluto.org'}),
        isNull,
      );
    });
  });

  group('DeviceProfile', () {
    test('동/호를 서버가 받는 유일한 형태로 조립한다', () {
      const profile = DeviceProfile(
        uuid: 'u',
        email: 'a@b.c',
        complexId: 'c',
        complexName: '단지',
        complexHost: 'example.test',
        building: '101',
        unit: '805',
        apiSecret: 's',
      );
      expect(profile.address, '101B805U');
    });

    test('릴레이는 단지 호스트, Janus 는 별도 호스트다', () {
      const profile = DeviceProfile(
        uuid: 'u',
        email: 'a@b.c',
        complexId: 'c',
        complexName: '단지',
        complexHost: 'example.test',
        building: '101',
        unit: '805',
        apiSecret: 's',
      );
      // 단말 등록은 단지 호스트로 간다.
      expect(profile.relayUrl, 'https://example.test/relay/register/mobile');
      // Janus 는 단지 호스트에서 조립하지 않는다 — 프로토콜이 다른 별개 서버다.
      expect(profile.janusUrl, isNot(contains('example.test')));
      expect(profile.janusUrl, endsWith('/janus-ws'));
    });

    test('SIP 자격은 완결 조건에 들어가지 않는다 — 등록해 봐야 받는 값이다', () {
      const profile = DeviceProfile(
        uuid: 'u',
        email: 'a@b.c',
        complexId: 'c',
        complexName: '단지',
        complexHost: 'example.test',
        building: '101',
        unit: '805',
        apiSecret: 's',
      );
      expect(profile.sip, isNull);
      expect(profile.isComplete, isTrue);
    });
  });
}
