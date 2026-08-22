import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/sip_config.dart';

/// rtc-relay 단말 등록 결과.
class DeviceRegistrationResult {
  const DeviceRegistrationResult({
    required this.ok,
    required this.statusCode,
    required this.message,
  });

  final bool ok;
  final int statusCode;
  final String message;
}

/// 착신(인터폰 → 모바일)을 받기 위해 FCM 토큰과 SIP 내선을 서버에 이어 준다.
///
/// 이걸 하지 않으면 Kamailio 가 붙들어 둔 INVITE 를 흘려보낼 단말을 찾지 못한다.
/// 발신만 할 거라면 없어도 된다.
class DeviceRegistrationService {
  DeviceRegistrationService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// `sip_user` 에 쓸 수 있는 문자와 길이 제한.
  static final RegExp _sipUserPattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

  static bool isValidSipUser(String value) => _sipUserPattern.hasMatch(value);

  /// 단말을 등록한다.
  ///
  /// [sipUser] 는 Kamailio 에 만든 내선과 **같아야** 한다. 다르면 푸시는 나가는데
  /// 통화는 안 되는 상태가 된다. null 이면 서버의 기존 값을 건드리지 않는다
  /// (빈 문자열을 보내면 연결이 끊기므로 아예 넣지 않는다).
  Future<DeviceRegistrationResult> registerMobile({
    required String uuid,
    required String email,
    required String complex,
    required String address,
    required String fcmToken,
    String? sipUser,
    String? signalingUrl,
  }) async {
    if (sipUser != null && !isValidSipUser(sipUser)) {
      return const DeviceRegistrationResult(
        ok: false,
        statusCode: 0,
        message: 'sip_user 는 A-Z a-z 0-9 . _ - 만 64자까지 쓸 수 있습니다.',
      );
    }

    // 경로 끝의 /mobile 이 빠지면 404 다.
    final url = SipConfig.deviceRegistrationUrl(signalingUrl: signalingUrl);
    final body = <String, dynamic>{
      'uuid': uuid,
      'email': email,
      'complex': complex,
      'address': address,
      'token': fcmToken,
      if (sipUser != null && sipUser.isNotEmpty) 'sip_user': sipUser,
    };

    try {
      final response = await _client
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      final ok = response.statusCode >= 200 && response.statusCode < 300;
      return DeviceRegistrationResult(
        ok: ok,
        statusCode: response.statusCode,
        message: ok ? '단말 등록 완료' : _messageOf(response.body, response.statusCode),
      );
    } catch (e) {
      return DeviceRegistrationResult(
        ok: false,
        statusCode: 0,
        message: '단말 등록 요청에 실패했습니다: $e',
      );
    }
  }

  String _messageOf(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return '$statusCode: ${decoded['error']}';
      }
    } catch (_) {
      // JSON 이 아니면 원문 앞부분을 그대로 보여준다.
    }
    final trimmed = body.trim();
    return '$statusCode: ${trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed}';
  }

  void dispose() => _client.close();
}
