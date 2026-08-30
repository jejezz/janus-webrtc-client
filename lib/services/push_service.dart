import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 인터폰이 걸었을 때 앱을 깨우는 FCM 경로.
///
/// 서버와의 계약은 NOTES.md 에 있다. Kamailio 가 INVITE 를 붙들어 두고
/// rtc-relay 를 통해 data 메시지를 보낸다.
///
/// ```json
/// { "method": "sip-incoming", "aor": "1001", "caller": "…", "callId": "…" }
/// ```
///
/// **60초 안에** Janus 에 붙어 register 까지 마쳐야 붙들린 INVITE 가 흘러온다
/// (Kamailio 의 wt_timer). 그래서 여기서는 앱을 띄우는 것까지만 하고, 등록은
/// ConnectScreen 이 저장된 접속 정보로 알아서 이어 간다 — 로그인 화면을 거치면
/// 그 시간을 까먹는다.
///
/// `google-services.json` 이 없으면 초기화가 실패하는데, 그때는 조용히 꺼진 채로
/// 둔다. 발신은 푸시 없이도 되므로 앱 전체를 막을 이유가 없다.
abstract final class PushService {
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'janus_incoming',
    '착신',
    description: '인터폰이 호출했을 때 울립니다',
    // 화면을 켜고 통화 화면을 띄우려면 최고 중요도여야 한다.
    importance: Importance.max,
  );

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// 착신 알림 id. 새 호출이 와도 하나만 유지한다.
  static const int _incomingId = 2001;

  static bool _available = false;

  /// 승인 결과 푸시. 대기 화면이 이걸 듣고 스스로 다음으로 넘어간다.
  ///
  /// 서버는 승인·거절·만료를 `enroll.approved` / `enroll.rejected` /
  /// `enroll.expired` 로 보낸다. 이걸 듣지 않으면 사용자가 "다시 확인" 을 눌러
  /// 볼 때까지 대기 화면에 머문다.
  static final ValueNotifier<String?> enrollmentEvent =
      ValueNotifier<String?>(null);

  /// FCM 을 쓸 수 있는 상태인지. 설정 파일이 없으면 false 로 남는다.
  static bool get isAvailable => _available;

  /// 앱 시작 시 한 번.
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // google-services.json 이 없거나 잘못된 경우다. 착신만 못 받을 뿐이다.
      debugPrint('FCM 비활성 — Firebase 초기화 실패: $e');
      _available = false;
      return;
    }

    try {
      await _setUpNotifications();
      await FirebaseMessaging.instance.requestPermission();
      FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      _available = true;
      debugPrint('FCM 준비됨');
    } catch (e) {
      debugPrint('FCM 설정 실패: $e');
      _available = false;
    }
  }

  /// rtc-relay 에 등록할 단말 토큰.
  static Future<String?> token() async {
    if (!_available) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FCM 토큰 조회 실패: $e');
      return null;
    }
  }

  static Future<void> _setUpNotifications() async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_call'),
      ),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    final method = (message.data['method'] ?? '').toString();
    debugPrint('[push] $method ${message.data}');

    if (method.startsWith('enroll.')) {
      enrollmentEvent.value = method;
      return;
    }
    // 앱이 떠 있으면 이미 등록돼 있어 곧 incomingcall 이벤트가 온다.
    // 화면이 다른 곳에 가 있을 수 있으니 알림만 띄운다.
    await showIncomingCall(message);
  }

  /// 착신 알림. 화면이 꺼져 있어도 통화 화면이 뜨도록 full-screen intent 를 건다.
  static Future<void> showIncomingCall(RemoteMessage message) async {
    if (message.data['method'] != 'sip-incoming') return;
    final caller = (message.data['caller'] ?? '').toString().trim();

    await _notifications.show(
      id: _incomingId,
      title: '인터폰 호출',
      body: caller.isEmpty ? '연결하려면 누르세요' : caller,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          // 잠금 화면에서도 바로 통화 화면을 띄운다.
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: true,
        ),
      ),
    );
  }

  static Future<void> dismissIncomingCall() async {
    try {
      await _notifications.cancel(id: _incomingId);
    } catch (e) {
      debugPrint('착신 알림 정리 실패: $e');
    }
  }
}

/// 앱이 꺼져 있을 때 푸시를 받는 자리.
///
/// 별도 isolate 에서 도므로 앱의 상태를 볼 수 없다. 할 수 있는 것은 알림을 띄워
/// 앱을 띄우는 것까지다. 최상위 함수여야 하고 vm:entry-point 가 있어야 한다.
@pragma('vm:entry-point')
Future<void> handleBackgroundMessage(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    await PushService._setUpNotifications();
    await PushService.showIncomingCall(message);
  } catch (e) {
    debugPrint('백그라운드 푸시 처리 실패: $e');
  }
}
