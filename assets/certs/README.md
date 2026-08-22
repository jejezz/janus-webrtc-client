# 사설 CA 인증서 자리

개발 Janus 서버(`jejezzhome.iptime.org:28443`)의 인증서는 사설 CA `DevCA Root` 가
발급한 것이라, Flutter 기본 신뢰 저장소로는 검증에 실패한다.

```
CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate
```

인증서 자체는 문제가 없다. SAN 에 `jejezzhome.iptime.org`, `192.168.0.252`,
`125.242.8.15` 가 모두 들어 있고 유효기간도 2027-08-14 까지다. **발급자 신뢰만
없는 상태**다.

## 해결

`DevCA Root` 의 공개 인증서를 PEM 형식으로 이 디렉터리에 **`dev_ca.pem`** 이라는
이름으로 두면 된다. 앱 시작 시 `lib/config/tls_bootstrap.dart` 가 이걸 읽어
Dart 의 기본 `SecurityContext` 에 추가한다. 넣을 것은 CA 의 **공개 인증서**이며,
개인키(`.key`)는 절대 앱에 넣지 않는다.

서버에서 꺼내는 예:

```bash
sudo find /etc/ssl /etc/nginx /root -name '*.crt' 2>/dev/null | xargs -I{} sh -c 'openssl x509 -in {} -noout -subject 2>/dev/null | grep -q "DevCA Root" && echo {}'
```

찾은 파일이 이미 PEM(`-----BEGIN CERTIFICATE-----` 로 시작)이면 그대로 복사하고,
DER 형식이면 변환한다:

```bash
openssl x509 -inform DER -in DevCA-Root.der -out dev_ca.pem
```

넣은 뒤에는 애셋이 새로 번들되도록 다시 빌드한다 (핫 리로드로는 반영되지 않는다).

## CA 를 아직 못 구했을 때

이 파일이 없으면 **디버그 빌드는 자동으로** `JanusConfig.devTrustedHosts` 에 한해
인증서 검증을 건너뛴다. 별도 플래그가 필요 없고, 릴리스 빌드에는 영향이 없다.
앱 시작 로그에 경고 상자가 찍힌다.

`dev_ca.pem` 을 넣는 순간 이 우회는 자동으로 꺼지고 정상 검증으로 돌아간다.
디버그 빌드에서도 엄격하게 검증하려면:

```bash
flutter run --dart-define=JANUS_STRICT_TLS=true
```

## 참고

Android 의 `network_security_config.xml` 은 이 문제를 해결하지 못한다. 그 설정은
Java/Kotlin 계층(OkHttp, WebView)에만 적용되고, `dart:io` 소켓은 Flutter 에 내장된
자체 CA 목록을 쓰기 때문이다.
