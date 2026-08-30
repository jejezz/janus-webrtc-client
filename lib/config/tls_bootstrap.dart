import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'janus_config.dart';

/// 앱에 동봉하는 사설 CA 인증서 경로 (PEM).
const String _caAssetPath = 'assets/certs/dev_ca.pem';

/// Janus 서버의 TLS 를 Dart 쪽에서 신뢰하도록 준비한다. `runApp` 전에 한 번 부른다.
///
/// 주의: Android 의 `network_security_config.xml` 은 Java/Kotlin 계층(OkHttp,
/// WebView)에만 적용된다. `dart:io` 소켓 — 즉 `WebSocket.connect` 와
/// `web_socket_channel`, 따라서 janus_client 의 트랜스포트 — 은 Flutter 에 내장된
/// 자체 루트 CA 목록을 쓰므로 시스템 신뢰 저장소나 사용자 설치 CA 를 보지 않는다.
/// 사설 CA 로 서명된 서버에 붙으려면 반드시 여기서 처리해야 한다.
///
/// 우선순위:
/// 1. [_caAssetPath] 에 CA 가 있으면 Dart 기본 [SecurityContext] 에 추가한다.
///    인증서 검증이 그대로 유지되므로 이 방법이 정석이다.
/// 2. CA 가 없는 디버그 빌드라면 [JanusConfig.devTrustedHosts] 에 한해 검증을
///    건너뛴다. 개발 서버가 사설 CA 를 쓰는 동안 매번 플래그를 붙이지 않아도
///    되게 하기 위한 것이고, `--dart-define=JANUS_STRICT_TLS=true` 로 끌 수 있다.
/// 3. 릴리스 빌드거나 엄격 모드면 아무것도 하지 않는다.
Future<void> configureJanusTls() async {
  if (await _trustBundledCa()) return;

  final hosts = JanusConfig.devTrustedHosts;
  if (kDebugMode && !JanusConfig.strictTls && hosts.isNotEmpty) {
    HttpOverrides.global = _DevCertificateOverrides(hosts);
    debugPrint(
      '\n'
      '┌──────────────────────────────────────────────────────────────\n'
      '│ [TLS] 인증서 검증을 건너뜁니다 — 디버그 빌드 전용\n'
      '│ 대상 호스트: ${hosts.join(', ')}\n'
      '│ $_caAssetPath 에 CA(PEM) 를 넣으면 정상 검증으로 복구됩니다.\n'
      '│ 디버그에서도 엄격 검증: --dart-define=JANUS_STRICT_TLS=true\n'
      '└──────────────────────────────────────────────────────────────\n',
    );
    return;
  }

  debugPrint(
    '[TLS] 사설 CA 가 설정되지 않았습니다. 서버가 사설 CA 를 쓴다면 '
    '$_caAssetPath 에 CA(PEM) 를 넣으세요.',
  );
}

/// 동봉된 CA 를 Dart 기본 신뢰 저장소에 추가한다. 성공하면 true.
Future<bool> _trustBundledCa() async {
  try {
    final data = await rootBundle.load(_caAssetPath);
    SecurityContext.defaultContext.setTrustedCertificatesBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    debugPrint('[TLS] 사설 CA 를 신뢰 목록에 추가했습니다: $_caAssetPath');
    return true;
  } on FlutterError {
    // 애셋이 없는 경우. 정상적인 분기다.
    return false;
  } on TlsException catch (e) {
    // 파일은 있으나 PEM 이 아니거나 깨진 경우.
    debugPrint('[TLS] CA 를 읽지 못했습니다 ($_caAssetPath): $e');
    return false;
  }
}

/// 지정한 호스트에 한해서만 인증서 검증을 건너뛰는 디버그 전용 오버라이드.
///
/// [HttpClient] 는 `WebSocket.connect` 내부에서도 이 오버라이드를 통해 만들어지므로
/// WebSocket 트랜스포트에도 적용된다.
class _DevCertificateOverrides extends HttpOverrides {
  _DevCertificateOverrides(this.allowedHosts);

  final Set<String> allowedHosts;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (cert, host, port) => allowedHosts.contains(host);
  }
}
