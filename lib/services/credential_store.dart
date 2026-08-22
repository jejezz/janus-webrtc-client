import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 기기에 저장해 두는 접속 정보.
class SipCredentials {
  const SipCredentials({
    required this.serverUrl,
    required this.apiSecret,
    required this.extension,
    required this.password,
  });

  const SipCredentials.empty()
      : serverUrl = '',
        apiSecret = '',
        extension = '',
        password = '';

  final String serverUrl;
  final String apiSecret;
  final String extension;
  final String password;

  /// 네 값이 모두 있어야 사용자 개입 없이 등록을 시작할 수 있다.
  bool get isComplete =>
      serverUrl.isNotEmpty &&
      apiSecret.isNotEmpty &&
      extension.isNotEmpty &&
      password.isNotEmpty;
}

/// 접속 정보를 기기에 보관한다.
///
/// 비밀번호가 섞여 있으므로 평문으로 남는 SharedPreferences 대신 iOS 키체인과
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

  static const _keyServerUrl = 'sip.server_url';
  static const _keyApiSecret = 'sip.api_secret';
  static const _keyExtension = 'sip.extension';
  static const _keyPassword = 'sip.password';

  /// 저장된 값을 읽는다. 일부만 있어도 설정 화면을 채울 수 있도록 그대로 돌려준다.
  Future<SipCredentials> load() async {
    final values = await Future.wait([
      _storage.read(key: _keyServerUrl),
      _storage.read(key: _keyApiSecret),
      _storage.read(key: _keyExtension),
      _storage.read(key: _keyPassword),
    ]);
    return SipCredentials(
      serverUrl: values[0] ?? '',
      apiSecret: values[1] ?? '',
      extension: values[2] ?? '',
      password: values[3] ?? '',
    );
  }

  Future<void> save(SipCredentials credentials) async {
    await Future.wait([
      _storage.write(key: _keyServerUrl, value: credentials.serverUrl),
      _storage.write(key: _keyApiSecret, value: credentials.apiSecret),
      _storage.write(key: _keyExtension, value: credentials.extension),
      _storage.write(key: _keyPassword, value: credentials.password),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _keyServerUrl),
      _storage.delete(key: _keyApiSecret),
      _storage.delete(key: _keyExtension),
      _storage.delete(key: _keyPassword),
    ]);
  }
}
