import 'package:flutter_test/flutter_test.dart';
import 'package:janus_client_app/config/sip_config.dart';
import 'package:janus_client_app/services/device_registration_service.dart';

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
        'https://example.test:28443/rtc-relay/register/mobile',
      );
      expect(
        SipConfig.deviceRegistrationUrl(
            signalingUrl: 'ws://192.168.0.9:8188/janus-ws'),
        'http://192.168.0.9:8188/rtc-relay/register/mobile',
      );
    });
  });

  group('DeviceRegistrationService', () {
    test('sip_user 는 허용 문자 64자까지만 받는다', () {
      expect(DeviceRegistrationService.isValidSipUser('1001'), isTrue);
      expect(DeviceRegistrationService.isValidSipUser('a.b_c-1'), isTrue);
      expect(DeviceRegistrationService.isValidSipUser(''), isFalse);
      expect(DeviceRegistrationService.isValidSipUser('has space'), isFalse);
      expect(DeviceRegistrationService.isValidSipUser('a' * 65), isFalse);
    });
  });
}
