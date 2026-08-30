import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:janus_client/janus_client.dart';
import 'package:logging/logging.dart';

import '../config/janus_config.dart';

/// 사용자에게 그대로 보여줄 메시지를 담은 연결 실패 신호.
class JanusConnectionException implements Exception {
  JanusConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Janus 세션을 열고 **각 단계가 실제로 성공했는지 확인**한다.
///
/// janus_client 2.4.4 는 실패를 조용히 삼킨다.
///
/// - `JanusClient.createSession()` 은 `create` 가 거절돼도 예외를 삼키고
///   (`catch (e) { _logger.severe(e); }`) `sessionId` 가 null 인 세션을 돌려준다.
/// - `JanusSession.attach()` 도 응답에 `data` 가 없으면 `handleId` 를 null 로 둔
///   플러그인을 그대로 돌려준다.
/// - `WebSocketJanusTransport.send()` 는 `payload['session_id'] = sessionId` 를
///   무조건 넣으므로, 위 상태에서는 **null 이 실려 나간다.**
///
/// 그래서 `create` 가 403 한 번 맞으면 뒤이은 `attach` 와 `message` 가 전부
/// `session_id: null` 로 나가고, 서버 로그에는 세 요청이 같은 순간에 몰려
/// 실패한 것처럼 보인다. 앱은 아무 오류도 못 보고 조용히 멈춘다.
///
/// 여기서는 단계마다 결과를 확인하고, 삼켜진 원인을 로거로 가로채 그대로
/// 사용자에게 전달한다.
class JanusConnection {
  JanusConnection._(this.client, this.transport, this.session, this._log);

  final JanusClient client;
  final JanusTransport transport;
  final JanusSession session;
  final _SwallowedErrorLog _log;

  static const Duration defaultTimeout = Duration(seconds: 20);

  /// 세션을 열고 `sessionId` 가 실제로 발급됐는지 확인한다.
  static Future<JanusConnection> open({
    required String serverUrl,
    required String apiSecret,
    required int refreshIntervalSeconds,
    String token = '',
    Duration timeout = defaultTimeout,
  }) async {
    final secret = apiSecret.trim();
    final janusToken = token.trim();
    final log = _SwallowedErrorLog();
    final transport = JanusConfig.transportFor(serverUrl);

    final client = JanusClient(
      transport: transport,
      iceServers: JanusConfig.iceServers,
      isUnifiedPlan: true,
      // 자격은 모든 요청에 실려야 한다. 빠지면 전부 403.
      //
      // 토큰이 있으면 그것이 이 단말의 자격이다. 공유 시크릿은 전환이 끝날
      // 때까지만 함께 싣는다.
      withCredentials: secret.isNotEmpty || janusToken.isNotEmpty,
      apiSecret: secret.isNotEmpty ? secret : null,
      token: janusToken.isNotEmpty ? janusToken : null,
      refreshInterval: refreshIntervalSeconds,
      // 자체 로거를 넘겨 삼켜지는 오류를 가로챈다.
      logger: log.logger,
    );

    JanusSession? session;
    try {
      // TLS 핸드셰이크 실패는 예외가 아니라 전송 대기로만 드러난다.
      session = await client.createSession().timeout(
            timeout,
            onTimeout: () => throw JanusConnectionException(
              '서버가 응답하지 않습니다.\n$serverUrl\n\n'
              '주소와 TLS 인증서를 확인하세요.',
            ),
          );

      if (session.sessionId == null) {
        throw JanusConnectionException(
          'Janus 세션을 만들지 못했습니다.\n'
          '${log.lastError ?? 'create 요청이 거절되었습니다.'}\n\n'
          'API Secret, 주소, TLS 인증서를 확인하세요.',
        );
      }
    } catch (_) {
      // 실패한 채로 두면 트랜스포트의 자동 재연결 루프가 계속 돌면서
      // 처리되지 않는 예외를 던진다. 여기서 확실히 닫는다.
      session?.dispose();
      transport.dispose();
      rethrow;
    }

    return JanusConnection._(client, transport, session, log);
  }

  /// 플러그인을 붙이고 `handleId` 가 실제로 발급됐는지 확인한다.
  Future<T> attach<T extends JanusPlugin>({
    Duration timeout = defaultTimeout,
  }) async {
    final plugin = await session.attach<T>().timeout(
          timeout,
          onTimeout: () => throw JanusConnectionException(
            'attach 응답이 없습니다. 서버 상태를 확인하세요.',
          ),
        );

    if (plugin.handleId == null) {
      throw JanusConnectionException(
        '플러그인 핸들을 얻지 못했습니다.\n'
        '${_log.lastError ?? '서버가 attach 를 거절했습니다.'}\n\n'
        '해당 플러그인이 서버에 올라가 있는지 확인하세요.',
      );
    }
    return plugin;
  }

  /// 시그널링 전송이 아직 살아 있는지.
  ///
  /// WebSocket 은 백그라운드 전환이나 네트워크 변경으로 조용히 끊긴다. 그때
  /// `JanusPlugin.send()` 는 삼킨 예외 대신 null 을 돌려주고, 그 null 이
  /// `JanusEvent.fromJson` 으로 들어가 엉뚱한 NoSuchMethodError 로 둔갑한다.
  /// 보내기 전에 여기서 먼저 걸러야 사용자에게 제대로 된 이유를 줄 수 있다.
  bool get isAlive {
    final ws = transport;
    if (ws is WebSocketJanusTransport) return ws.isConnected;
    return true;   // REST 는 연결 개념이 없다.
  }

  /// janus_client 가 삼킨 마지막 오류.
  String? get lastSwallowedError => _log.lastError;

  void dispose() => session.dispose();
}

/// janus_client 가 `_logger.severe(...)` 로 삼켜 버리는 원인을 붙잡아 둔다.
///
/// 자체 로거를 넘기면 janus_client 는 로깅을 일절 관리하지 않으므로 레벨 설정과
/// 출력까지 여기서 맡는다.
class _SwallowedErrorLog {
  _SwallowedErrorLog() : logger = Logger.detached('JanusClient') {
    // JanusPlugin.send() 는 삼킨 예외를 FINE 으로 흘린다. WARNING 으로 막아 두면
    // 정작 알아야 할 "WebSocket is not connected" 를 놓친다.
    logger.level = Level.FINE;
    logger.onRecord.listen((record) {
      if (record.level >= Level.FINE) {
        lastError = record.message.toString();
      }
      if (kDebugMode || record.level >= Level.WARNING) {
        debugPrint('[janus] ${record.level.name}: ${record.message}');
      }
    });
  }

  final Logger logger;

  /// 마지막으로 삼켜진 오류 메시지.
  String? lastError;
}
