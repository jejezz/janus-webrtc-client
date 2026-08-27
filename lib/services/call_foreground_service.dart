import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 통화 중에만 뜨는 안드로이드 포그라운드 서비스를 켜고 끈다.
///
/// 안드로이드 11+ 는 포그라운드가 아닌 앱의 녹음을 침묵 처리한다. 통화 중에 홈으로
/// 나가면 마이크가 조용히 끊겨 상대는 아무 소리도 못 듣는다. 그걸 막으려면
/// `foregroundServiceType=microphone` 서비스가 떠 있어야 한다.
///
/// iOS 는 해당 없음 — 백그라운드 오디오는 Info.plist 의 background modes 로 다룬다.
abstract final class CallForegroundService {
  static const MethodChannel _channel = MethodChannel('janus/call_service');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// 통화가 시작될 때. [peer] 는 알림에 보여 줄 상대 표시다.
  static Future<void> start({String? peer}) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('start', {'peer': peer});
    } catch (e) {
      // 서비스를 못 띄워도 통화 자체는 계속돼야 한다. 화면을 벗어났을 때만
      // 마이크가 끊길 뿐이다.
      debugPrint('통화 포그라운드 서비스 시작 실패: $e');
    }
  }

  static Future<void> stop() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('통화 포그라운드 서비스 종료 실패: $e');
    }
  }
}
