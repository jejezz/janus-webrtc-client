import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  /// 등록 응답으로 받아 둔 SIP 자격. 없을 수 있다 — 번호를 받기 전에 승인된
  /// 옛 단말이거나 숫자가 아닌 동/호인 세대다.
  final SipAccount? sip;

  /// 서버가 받는 유일한 형태다.
  String get address => '${building.trim()}B${unit.trim()}U';

  /// 단지 호스트에서 조립한 시그널링 주소.
  ///
  /// 단지 목록의 host 에는 **포트가 없다**(있으면 형식 오류로 버려진다). 즉 443
  /// 을 전제로 한다. 포트가 다른 개발 서버로 붙어 볼 때는 아래 값을 넘긴다.
  ///
  /// ```
  /// flutter run --dart-define=JANUS_URL=wss://호스트:28443/janus-ws
  /// ```
  String get janusUrl {
    const override = String.fromEnvironment('JANUS_URL');
    if (override.isNotEmpty) return override;
    return 'wss://$complexHost/janus-ws';
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
    ]);

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
      apiSecret: values[7] ?? '',
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
