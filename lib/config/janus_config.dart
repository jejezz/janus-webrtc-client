import 'package:janus_client/janus_client.dart';

/// Janus 서버 접속에 필요한 기본값 모음.
///
/// 화면에서 서버 주소/방 정보를 직접 입력할 수 있으므로 여기 값들은 초기값이다.
/// 배포 시에는 `--dart-define` 으로 주입하는 편이 안전하다.
class JanusConfig {
  const JanusConfig._();

  /// Janus 시그널링 주소.
  ///
  /// `ws://` `wss://` 는 WebSocket 트랜스포트로, `http://` `https://` 는 REST
  /// 트랜스포트로 붙는다. 어느 쪽이 가능한지는 서버의 `/info` 응답 `transports`
  /// 항목에 달려 있다.
  ///
  /// Android 에뮬레이터에서 개발용 PC 를 볼 때는 `localhost` 대신 `10.0.2.2` 를
  /// 쓴다. 실기기라면 PC 의 LAN IP 를 넣는다.
  static const String defaultServerUrl = String.fromEnvironment(
    'JANUS_SERVER_URL',
    defaultValue: 'wss://www.zoomon.art/janus-ws',
  );

  /// VideoRoom 기본 방 번호. janus.plugin.videoroom.jcfg 의 기본 방이 1234 다.
  static const String defaultRoom = String.fromEnvironment(
    'JANUS_ROOM',
    defaultValue: '1234',
  );

  /// janus.jcfg 에 `api_secret` 이 설정된 서버라면 반드시 필요하다.
  /// 참가 화면에서 직접 입력할 수도 있고, 여기 기본값으로 주입해 둘 수도 있다.
  static const String defaultApiSecret =
      String.fromEnvironment('JANUS_API_SECRET');

  /// 디버그 빌드에서도 인증서 검증을 엄격하게 유지할지 여부.
  ///
  /// 기본값은 false 다. 즉 디버그 빌드는 [devTrustedHosts] 에 한해 검증을
  /// 건너뛴다. 사설 CA 를 쓰는 개발 서버에 매번 플래그 없이 붙기 위한 선택이며
  /// 릴리스 빌드에는 영향이 없다. `assets/certs/dev_ca.pem` 을 넣으면 이 우회는
  /// 자동으로 비활성화되고 정상 검증으로 돌아간다.
  ///
  /// 디버그에서도 엄격하게 검증하려면 `--dart-define=JANUS_STRICT_TLS=true`.
  static const bool strictTls = bool.fromEnvironment('JANUS_STRICT_TLS');

  /// 디버그 빌드에서 인증서 검증을 건너뛸 호스트 목록.
  /// 기본값은 [defaultServerUrl] 의 호스트 하나뿐이라 다른 서버까지 열리지 않는다.
  static Set<String> get devTrustedHosts {
    final host = Uri.tryParse(defaultServerUrl)?.host;
    return {
      if (host != null && host.isNotEmpty) host,
      ...const String.fromEnvironment('JANUS_DEV_TRUSTED_HOSTS')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty),
    };
  }

  /// NAT 뒤에서 붙을 때 필요한 ICE 서버. 실제 운영에서는 TURN 을 반드시 추가한다.
  static List<RTCIceServer> get iceServers => [
        RTCIceServer(urls: 'stun:stun.l.google.com:19302'),
      ];

  /// publish 할 로컬 카메라 제약 조건.
  static const Map<String, dynamic> localMediaConstraints = {
    'audio': true,
    'video': {
      'width': 640,
      'height': 480,
      'facingMode': 'user',
    },
  };

  /// URL 스킴을 보고 알맞은 트랜스포트를 만든다.
  ///
  /// REST 트랜스포트는 long-poll 로 이벤트를 받으므로 WebSocket 보다 지연이 크다.
  /// 서버가 janus.transport.websockets 를 올려 두었다면 그쪽을 쓰는 편이 낫다.
  static JanusTransport transportFor(String url) {
    final uri = Uri.parse(url);
    if (uri.isScheme('http') || uri.isScheme('https')) {
      return RestJanusTransport(url: url);
    }
    return WebSocketJanusTransport(
      url: url,
      // 자동 재연결을 끈다. 소켓만 다시 붙어도 janus_client 는 세션을 새로
      // 만들거나 핸들을 다시 attach 하지 않아서, 살아난 소켓으로 보내는 요청은
      // 여전히 죽은 session_id 를 달고 나간다. 게다가 재연결 루프는 실패할 때마다
      // 처리되지 않는 예외를 던진다. 끊기면 명시적으로 다시 등록하는 편이 낫다.
      autoReconnect: false,
    );
  }

  /// [transportFor] 가 받아들이는 스킴인지 검사한다.
  static bool isSupportedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.isScheme('ws') ||
        uri.isScheme('wss') ||
        uri.isScheme('http') ||
        uri.isScheme('https');
  }
}
