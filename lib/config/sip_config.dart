import 'janus_config.dart';

/// SIP 계정과 프록시 설정. 값은 서버 구성에 맞춰 고정돼 있다 (NOTES.md 참고).
class SipConfig {
  const SipConfig._();

  /// SIP 도메인. 내선 번호를 `sip:<내선>@<도메인>` 으로 조립할 때 쓴다.
  static const String domain = String.fromEnvironment(
    'SIP_DOMAIN',
    defaultValue: 'pluto.org',
  );

  /// REGISTER 를 보낼 곳.
  static const String proxy = String.fromEnvironment(
    'SIP_PROXY',
    defaultValue: 'sip:192.168.0.252:5060',
  );

  /// INVITE 를 실제로 내보낼 곳.
  ///
  /// 이 값을 빠뜨리면 INVITE 목적지가 요청 URI 의 도메인으로 정해진다.
  /// [domain] 은 실재하는 공인 도메인이라 DNS 로 풀려 INVITE 가 인터넷으로 나가고,
  /// Kamailio 는 그것을 아예 보지 못한다 — 로그도 응답도 없이 조용히 실패한다.
  static const String outboundProxy = String.fromEnvironment(
    'SIP_OUTBOUND_PROXY',
    defaultValue: 'sip:192.168.0.252:5060',
  );

  /// 다이얼러에 미리 채워 둘 상대 번호 (인터폰).
  static const String defaultCallee = String.fromEnvironment(
    'SIP_DEFAULT_CALLEE',
    defaultValue: '0010200601',
  );

  /// Janus 세션 타임아웃이 60초다. 그보다 넉넉히 짧게 keepalive 를 보낸다.
  static const int keepaliveIntervalSeconds = 30;

  /// 통화는 오디오 전용이다. 인터폰은 G.711 만 하므로 SDP 는 손대지 않는다.
  /// flutter_webrtc 기본 offer 에 PCMU/PCMA 가 들어 있고, 좁히면 소리가 끊긴다.
  static const Map<String, dynamic> callMediaConstraints = {
    'audio': true,
    'video': false,
  };

  /// 내선 번호나 전체 URI 를 받아 SIP URI 로 정규화한다.
  ///
  /// [domain] 은 등록된 계정의 도메인을 넘긴다. 서버가 배정한 자격에 도메인이
  /// 함께 오므로 그쪽이 맞다. 없으면 기본값으로 떨어진다.
  static String toSipUri(String value, {String? domain}) {
    final trimmed = value.trim();
    if (trimmed.startsWith('sip:') || trimmed.startsWith('sips:')) {
      return trimmed;
    }
    return 'sip:$trimmed@${domain?.trim().isNotEmpty == true ? domain!.trim() : SipConfig.domain}';
  }

  /// SIP URI 에서 사람이 읽을 부분(내선/번호)만 뽑는다.
  static String displayOf(String? uri) {
    if (uri == null || uri.isEmpty) return '알 수 없음';
    final withoutScheme = uri.replaceFirst(RegExp(r'^sips?:'), '');
    final at = withoutScheme.indexOf('@');
    return at > 0 ? withoutScheme.substring(0, at) : withoutScheme;
  }

  /// rtc-relay 단말 등록 주소.
  ///
  /// 시그널링과 같은 오리진에 있다. `wss://host:port/janus-ws` 에서
  /// `https://host:port/rtc-relay/register/mobile` 을 만든다.
  /// nginx 앞단의 경로 접두사는 배포마다 다르다. 이 저장소의 서버는
  /// `/rtc-relay`, 마이그레이션 문서의 예시는 `/iot`, 포트에 직접 붙으면
  /// 접두사가 없다. 값만 바꿔 맞춘다.
  static const String relayPath = String.fromEnvironment(
    'RTC_RELAY_PATH',
    defaultValue: '/rtc-relay/register/mobile',
  );

  static String deviceRegistrationUrl({String? signalingUrl}) {
    const override = String.fromEnvironment('RTC_RELAY_URL');
    if (override.isNotEmpty) return override;

    final uri = Uri.tryParse(signalingUrl ?? JanusConfig.defaultServerUrl);
    if (uri == null || uri.host.isEmpty) {
      return 'https://jejezzhome.iptime.org:28443$relayPath';
    }
    final scheme = uri.isScheme('ws') || uri.isScheme('http') ? 'http' : 'https';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://${uri.host}$port$relayPath';
  }
}
