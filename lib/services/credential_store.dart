import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/janus_config.dart';
import '../config/sip_config.dart';
import '../models/sip_account.dart';

/// 이 단말이 누구인지, 그리고 서버가 배정해 준 SIP 자격.
///
/// 내선 번호를 사람이 정하던 구조는 없어졌다. 서버가 승인 시점에 동/호에서
/// 번호를 계산해 배정하므로, 앱이 저장할 것은 **단지·세대·단말 식별자**이고
/// SIP 자격은 등록 응답으로 받아 캐시해 둘 뿐이다 (client-migration.md).
class DeviceProfile {
  const DeviceProfile({
    required this.uuid,
    required this.email,
    required this.complexId,
    required this.complexName,
    required this.complexHost,
    required this.building,
    required this.unit,
    required this.apiSecret,
    this.pushedJanusUrl = '',
    this.speakerByDefault = true,
    this.sip,
  });

  const DeviceProfile.empty()
      : uuid = '',
        email = '',
        complexId = '',
        complexName = '',
        complexHost = '',
        building = '',
        unit = '',
        apiSecret = '',
        pushedJanusUrl = '',
        speakerByDefault = true,
        sip = null;

  /// 서버가 단말을 가르는 열쇠. **한 번 만들면 바꾸지 않는다** — 바뀌면 서버에는
  /// 새 단말로 보이고, 옛 행이 세대의 자리(4대)를 차지한 채 남는다.
  final String uuid;
  final String email;

  final String complexId;
  final String complexName;

  /// 스킴 없는 호스트. 여기서 시그널링·등록 주소를 조립한다.
  final String complexHost;

  final String building;
  final String unit;

  /// Janus 의 api_secret. 단지 서버 구성에 딸린 값이라 사용자가 넣는다.
  final String apiSecret;

  /// 착신 푸시가 알려 준 Janus 주소. 비어 있으면 기본값을 쓴다.
  final String pushedJanusUrl;

  /// 통화가 연결되면 스피커를 켤지. 인터폰은 손에 들지 않고 쓰는 일이 많아
  /// 기본은 켬이다. 통화가 끝나면 원래대로 되돌린다.
  final bool speakerByDefault;

  /// 등록 응답으로 받아 둔 SIP 자격. 없을 수 있다 — 번호를 받기 전에 승인된
  /// 옛 단말이거나 숫자가 아닌 동/호인 세대다.
  final SipAccount? sip;

  /// 서버가 받는 유일한 형태다.
  String get address => '${building.trim()}B${unit.trim()}U';

  /// 우리 집 월패드 번호.
  ///
  /// 번호는 동4 + 호4 + 순번2 이고, 붙박이 장치(세대면 월패드)는 순번이 `00` 이다
  /// (client-migration.md). 101동 805호 → `0101080500`.
  ///
  /// 동/호가 없으면 빈 문자열이다 — 그때는 화면이 기본값으로 떨어진다.
  String get wallpadNumber {
    final dong = building.trim();
    final ho = unit.trim();
    if (dong.isEmpty || ho.isEmpty) return '';
    return '${dong.padLeft(4, '0')}${ho.padLeft(4, '0')}00';
  }

  /// 단말 등록을 보낼 곳. **단지 호스트**에 있다.
  String get relayUrl => 'https://$complexHost${SipConfig.relayPath}';

  /// Janus 시그널링 주소. **단지 호스트에서 조립한다.**
  ///
  /// 릴레이와 프로토콜은 다르지만 사는 곳은 같은 서버다. 그래서 Firestore 가
  /// 내려 준 단지 호스트를 그대로 쓰는 것이 맞다 — 이름을 하나로 박아 두면
  /// 단지가 늘어날 때 따라가지 못한다.
  ///
  /// TLS 도 이쪽이 옳다. 단지 호스트는 자기 이름으로 발급된 인증서를 내놓지만
  /// 박아 두었던 `www.zoomon.art` 는 그 인증서의 SAN 에 없어 hostname mismatch
  /// 로 막힌다. 디버그 빌드가 검증을 건너뛰고 있어서 드러나지 않았을 뿐이다.
  ///
  /// 우선순위: 착신 푸시가 실어 보낸 주소 → `--dart-define` 으로 지정한 개발
  /// 서버 → 단지 호스트.
  String get janusUrl {
    if (pushedJanusUrl.isNotEmpty) return pushedJanusUrl;
    if (JanusConfig.serverUrlOverride.isNotEmpty) {
      return JanusConfig.serverUrlOverride;
    }
    if (complexHost.isNotEmpty) return 'wss://$complexHost${JanusConfig.wsPath}';
    return JanusConfig.defaultServerUrl;
  }

  /// 등록을 시도할 수 있는 상태인지. SIP 자격은 여기 들어가지 않는다 — 그건
  /// 등록해 봐야 받는 값이다.
  bool get isComplete =>
      uuid.isNotEmpty &&
      email.isNotEmpty &&
      complexHost.isNotEmpty &&
      building.isNotEmpty &&
      unit.isNotEmpty;

  DeviceProfile copyWith({
    String? uuid,
    String? email,
    String? complexId,
    String? complexName,
    String? complexHost,
    String? building,
    String? unit,
    String? apiSecret,
    String? pushedJanusUrl,
    bool? speakerByDefault,
    SipAccount? sip,
  }) {
    return DeviceProfile(
      uuid: uuid ?? this.uuid,
      email: email ?? this.email,
      complexId: complexId ?? this.complexId,
      complexName: complexName ?? this.complexName,
      complexHost: complexHost ?? this.complexHost,
      building: building ?? this.building,
      unit: unit ?? this.unit,
      apiSecret: apiSecret ?? this.apiSecret,
      pushedJanusUrl: pushedJanusUrl ?? this.pushedJanusUrl,
      speakerByDefault: speakerByDefault ?? this.speakerByDefault,
      sip: sip ?? this.sip,
    );
  }
}

/// 단말 프로필을 기기에 보관한다.
///
/// SIP 비밀번호가 섞여 있으므로 평문으로 남는 SharedPreferences 대신 iOS 키체인과
/// Android Keystore(AES-GCM) 를 쓴다.
class CredentialStore {
  const CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? _defaultStorage;

  // Android 기본값이 이미 Keystore 로 감싼 AES-GCM 이라 따로 줄 옵션이 없다.
  // iOS 는 첫 잠금 해제 뒤부터 읽히게 해 둔다 — 착신은 화면이 잠긴 상태에서도
  // 앱이 깨어나 등록해야 하기 때문이다.
  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final FlutterSecureStorage _storage;

  static const _keyUuid = 'device.uuid';
  static const _keyEmail = 'device.email';
  static const _keyComplexId = 'device.complex_id';
  static const _keyComplexName = 'device.complex_name';
  static const _keyComplexHost = 'device.complex_host';
  static const _keyBuilding = 'device.building';
  static const _keyUnit = 'device.unit';
  static const _keyApiSecret = 'janus.api_secret';

  /// 내선을 직접 입력하던 시절의 키. 그때 저장해 둔 API Secret 을 그대로 쓸 수
  /// 있으므로 한 번 넘겨받는다 — 아니면 사용자가 32자리를 다시 쳐야 한다.
  static const _legacyApiSecret = 'sip.api_secret';
  static const _keyPushedJanus = 'janus.pushed_url';
  static const _keySpeakerDefault = 'call.speaker_default';
  static const _keySipUser = 'sip.user';
  static const _keySipDomain = 'sip.domain';
  static const _keySipPassword = 'sip.password';

  Future<DeviceProfile> load() async {
    final values = await Future.wait([
      _storage.read(key: _keyUuid),
      _storage.read(key: _keyEmail),
      _storage.read(key: _keyComplexId),
      _storage.read(key: _keyComplexName),
      _storage.read(key: _keyComplexHost),
      _storage.read(key: _keyBuilding),
      _storage.read(key: _keyUnit),
      _storage.read(key: _keyApiSecret),
      _storage.read(key: _keySipUser),
      _storage.read(key: _keySipDomain),
      _storage.read(key: _keySipPassword),
      _storage.read(key: _keyPushedJanus),
      _storage.read(key: _keySpeakerDefault),
    ]);

    // 새 키가 비었으면 옛 키를 본다.
    var apiSecret = values[7] ?? '';
    if (apiSecret.isEmpty) {
      apiSecret = await _storage.read(key: _legacyApiSecret) ?? '';
      if (apiSecret.isNotEmpty) {
        await _storage.write(key: _keyApiSecret, value: apiSecret);
      }
    }

    final sipUser = values[8] ?? '';
    final sipDomain = values[9] ?? '';
    final sipPassword = values[10] ?? '';

    return DeviceProfile(
      // 없으면 지금 만들어 둔다. 이후로는 이 값을 그대로 쓴다.
      uuid: values[0]?.isNotEmpty == true ? values[0]! : await _newUuid(),
      email: values[1] ?? '',
      complexId: values[2] ?? '',
      complexName: values[3] ?? '',
      complexHost: values[4] ?? '',
      building: values[5] ?? '',
      unit: values[6] ?? '',
      apiSecret: apiSecret,
      pushedJanusUrl: values[11] ?? '',
      // 저장된 적이 없으면 켬으로 둔다.
      speakerByDefault: values[12] != 'false',
      sip: sipUser.isEmpty || sipDomain.isEmpty || sipPassword.isEmpty
          ? null
          : SipAccount(
              user: sipUser,
              domain: sipDomain,
              password: sipPassword,
            ),
    );
  }

  Future<void> save(DeviceProfile profile) async {
    await Future.wait([
      _storage.write(key: _keyUuid, value: profile.uuid),
      _storage.write(key: _keyEmail, value: profile.email),
      _storage.write(key: _keyComplexId, value: profile.complexId),
      _storage.write(key: _keyComplexName, value: profile.complexName),
      _storage.write(key: _keyComplexHost, value: profile.complexHost),
      _storage.write(key: _keyBuilding, value: profile.building),
      _storage.write(key: _keyUnit, value: profile.unit),
      _storage.write(key: _keyApiSecret, value: profile.apiSecret),
      _storage.write(key: _keyPushedJanus, value: profile.pushedJanusUrl),
      _storage.write(
        key: _keySpeakerDefault,
        value: profile.speakerByDefault ? 'true' : 'false',
      ),
      _storage.write(key: _keySipUser, value: profile.sip?.user ?? ''),
      _storage.write(key: _keySipDomain, value: profile.sip?.domain ?? ''),
      _storage.write(key: _keySipPassword, value: profile.sip?.password ?? ''),
    ]);
  }

  /// SIP 자격만 갱신한다. 비밀번호는 자리를 물려받은 단말이 생기면 새로
  /// 발급되므로, 401 을 만나면 다시 받아 여기에 덮어쓴다.
  Future<void> saveSip(SipAccount? account) async {
    await Future.wait([
      _storage.write(key: _keySipUser, value: account?.user ?? ''),
      _storage.write(key: _keySipDomain, value: account?.domain ?? ''),
      _storage.write(key: _keySipPassword, value: account?.password ?? ''),
    ]);
  }

  Future<void> clear() async => _storage.deleteAll();

  /// 처음 한 번만 만든다. 만들자마자 저장해야 다음 실행에서 달라지지 않는다.
  Future<String> _newUuid() async {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // v4
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final uuid = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await _storage.write(key: _keyUuid, value: uuid);
    return uuid;
  }
}
