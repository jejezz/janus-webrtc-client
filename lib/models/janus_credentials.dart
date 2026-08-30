/// 서버가 내려주는 Janus 접속 정보.
///
/// API Secret 은 사람이 외워서 넣을 수 있는 값이 아니다. 승인 응답에 SIP
/// 비밀번호가 이미 실려 오므로 (client-migration.md ①) 같은 경로로 함께
/// 받는 것이 자연스럽다 — 그쪽이 더 민감한 값이고, 이미 TLS 위에서 승인된
/// 단말에만 간다.
///
/// 서버가 아직 안 실어 보내면 전부 빈 값이다. 그때는 설정에 사람이 넣은 값,
/// 그것도 없으면 빌드에 박아 둔 값으로 떨어진다 ([DeviceProfile.effectiveApiSecret]).
class JanusCredentials {
  const JanusCredentials({
    this.url = '',
    this.apiSecret = '',
    this.token = '',
  });

  static const empty = JanusCredentials();

  /// 등록 응답에서 Janus 정보를 읽는다.
  ///
  /// 서버가 어느 모양으로 실을지 정해지지 않아 둘 다 받는다 —
  /// `janus: {url, token, apiSecret}` 중첩과 최상위 `janusUrl`/`janusToken`.
  /// 착신 푸시는 이미 최상위 `janusUrl` 을 쓴다.
  static JanusCredentials fromJson(Map<String, dynamic> json) {
    final nested = json['janus'];
    final map = nested is Map ? nested : const {};

    String pick(List<String> keys, Map source) {
      for (final key in keys) {
        final value = (source[key] ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final url = pick(['url', 'janusUrl'], map).isNotEmpty
        ? pick(['url', 'janusUrl'], map)
        : pick(['janusUrl', 'janus_url'], json);
    final secret = pick(['apiSecret', 'api_secret', 'secret'], map).isNotEmpty
        ? pick(['apiSecret', 'api_secret', 'secret'], map)
        : pick(['janusApiSecret', 'janus_api_secret'], json);

    final token = pick(['token', 'janusToken'], map).isNotEmpty
        ? pick(['token', 'janusToken'], map)
        : pick(['janusToken', 'janus_token'], json);

    return JanusCredentials(url: url, apiSecret: secret, token: token);
  }

  final String url;

  /// 단지 하나에 하나뿐인 공유 값. [token] 이 있으면 쓰지 않는다.
  final String apiSecret;

  /// 이 단말만의 토큰. 승인 시점에 서버가 발급한다 — 한 대가 털려도 그 한 대만
  /// 막으면 되고, 승인을 거두면 통화도 함께 막힌다.
  final String token;

  bool get isEmpty => url.isEmpty && apiSecret.isEmpty && token.isEmpty;
}
