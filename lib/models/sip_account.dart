/// 서버가 배정해 내려주는 SIP 자격.
///
/// 앱이 내선 번호를 정하던 구조는 없어졌다. 서버가 승인 시점에 동/호에서 번호를
/// 계산해 배정하고 Kamailio 계정까지 만든다 (client-migration.md).
///
/// ```
///  0101 0805 01
///  └동4┘└호4┘└순번2┘
/// ```
class SipAccount {
  const SipAccount({
    required this.user,
    required this.domain,
    required this.password,
  });

  /// 등록 응답의 `sip` 를 읽는다. 없으면 null 이다 — 번호를 받기 전에 승인된
  /// 옛 단말이거나, 숫자가 아닌 동/호라 번호를 만들 수 없는 세대다. 그 경우
  /// SIP 착신만 없고 WebRTC 초인종은 그대로 동작해야 한다.
  static SipAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final user = (json['user'] ?? '').toString().trim();
    final domain = (json['domain'] ?? '').toString().trim();
    final password = (json['password'] ?? '').toString();
    if (user.isEmpty || domain.isEmpty || password.isEmpty) return null;
    return SipAccount(user: user, domain: domain, password: password);
  }

  final String user;
  final String domain;
  final String password;

  /// Janus 에 넘길 `sip:<user>@<domain>`.
  String get uri => 'sip:$user@$domain';

  @override
  bool operator ==(Object other) =>
      other is SipAccount &&
      other.user == user &&
      other.domain == domain &&
      other.password == password;

  @override
  int get hashCode => Object.hash(user, domain, password);
}
