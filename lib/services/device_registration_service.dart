import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../models/sip_account.dart';

/// rtc-relay 단말 등록 결과.
class DeviceRegistrationResult {
  const DeviceRegistrationResult({
    required this.ok,
    required this.statusCode,
    required this.message,
    this.status = '',
    this.account,
  });

  final bool ok;
  final int statusCode;
  final String message;

  /// 서버가 말한 승인 상태. `approved` 또는 `pending`.
  final String status;

  /// 서버가 배정한 SIP 자격. 없을 수 있다 — 번호를 받기 전에 승인된 옛 단말이나
  /// 숫자가 아닌 동/호인 세대다. 그 경우 SIP 착신만 못 쓰고 나머지는 그대로다.
  final SipAccount? account;

  /// 승인은 났지만 아직 자리를 기다리는 중.
  bool get isPending => status == 'pending';
}

/// 착신(인터폰 → 모바일)을 받기 위해 FCM 토큰과 SIP 내선을 서버에 이어 준다.
///
/// 이걸 하지 않으면 Kamailio 가 붙들어 둔 INVITE 를 흘려보낼 단말을 찾지 못한다.
/// 발신만 할 거라면 없어도 된다.
class DeviceRegistrationService {
  DeviceRegistrationService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// 단말을 등록하고 서버가 배정한 SIP 자격을 받아 온다.
  ///
  /// `sip_user` 는 보내지 않는다. 번호는 서버가 동/호에서 계산해 배정하며,
  /// 보내더라도 서버가 배정한 값이 이긴다 (client-migration.md).
  ///
  /// [fcmToken] 을 **빈 값으로 보내면 안 된다.** 이 호출은 저장된 토큰을
  /// 덮어쓰므로, 빈 문자열을 넣으면 그 단말의 푸시가 조용히 끊긴다.
  Future<DeviceRegistrationResult> registerMobile({
    required String uuid,
    required String email,
    required String complex,
    required String address,
    required String fcmToken,
    required String relayUrl,
  }) async {
    if (fcmToken.trim().isEmpty) {
      return const DeviceRegistrationResult(
        ok: false,
        statusCode: 0,
        message: 'FCM 토큰이 비어 있습니다.\n'
            '빈 값으로 등록하면 이 단말의 푸시가 끊깁니다.',
      );
    }

    // 릴레이는 단지 호스트에 있다. Janus 주소에서 조립하면 안 된다 — 둘은
    // 서로 다른 호스트이고 프로토콜도 다르다.
    final url = relayUrl;
    final body = <String, dynamic>{
      'uuid': uuid,
      'email': email,
      'complex': complex,
      'address': address,
      'token': fcmToken,
    };

    debugPrint('[relay] POST $url  address=$address complex=$complex');
    try {
      final response = await _client
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      final text = response.body;
      debugPrint('[relay] ${response.statusCode} '
          '${text.length > 300 ? '${text.substring(0, 300)}…' : text}');

      final ok = response.statusCode >= 200 && response.statusCode < 300;
      if (!ok) {
        return DeviceRegistrationResult(
          ok: false,
          statusCode: response.statusCode,
          message: _messageOf(text, response.statusCode),
        );
      }

      Map<String, dynamic>? decoded;
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) decoded = parsed;
      } catch (_) {
        // 본문이 JSON 이 아니어도 등록 자체는 성공이다.
      }

      final status = (decoded?['status'] ?? '').toString();
      final account = SipAccount.fromJson(decoded?['sip']);
      return DeviceRegistrationResult(
        ok: true,
        statusCode: response.statusCode,
        message: _successMessage(status, account),
        status: status,
        account: account,
      );
    } catch (e) {
      debugPrint('[relay] 요청 실패: $e');
      return DeviceRegistrationResult(
        ok: false,
        statusCode: 0,
        message: '단말 등록 요청에 실패했습니다: $e',
      );
    }
  }

  String _successMessage(String status, SipAccount? account) {
    if (status == 'pending') {
      return '승인 대기 중입니다.\n월패드에서 이 단말을 승인해야 합니다.';
    }
    if (account == null) {
      // 번호를 받기 전에 승인된 옛 단말이거나, 숫자가 아닌 동/호인 세대다.
      return '단말 등록 완료 — 다만 이 세대에는 배정된 SIP 번호가 없습니다.\n'
          'SIP 착신은 쓸 수 없고 WebRTC 초인종은 그대로 동작합니다.';
    }
    return '단말 등록 완료 · 내선 ${account.user}';
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
