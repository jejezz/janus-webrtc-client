# GotDoor

아파트 인터폰·월패드와 통화하고 문을 여는 모바일 앱. "I got the door" — 초인종이
울리면 내가 받고, 문도 내가 연다. Janus 의 SIP 플러그인을 통해 Kamailio 에 붙는다
(NOTES.md).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 앱 아이콘

주고받는 말풍선(통화) + 좌우로 퍼지는 WebRTC 시그널 아크 모티브의 전용 런처 아이콘을 쓴다.
가운데 말풍선은 `assets/icon/glyph_source.png` 를 그대로 얹으므로, 그림을 바꾸려면
그 파일만 교체하고 생성기를 다시 돌리면 된다(코드 수정 불필요).
아이콘은 이미지 편집기 대신 [tool/generate_app_icon.py](tool/generate_app_icon.py) 가 코드로 그리며,
색·형태 상수만 고친 뒤 아래 명령으로 iOS/Android 리소스를 한 번에 다시 만들 수 있다.

```bash
python3 tool/generate_app_icon.py   # 필요: pillow, numpy
```

생성물

- `assets/icon/` — 1024px 마스터(전체 / adaptive foreground / background)
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/` — Contents.json 에 적힌 전 사이즈(알파 없는 RGB)
- `android/.../mipmap-*/` — 레거시 `ic_launcher`·`ic_launcher_round`,
  adaptive icon 용 `foreground`/`background`/`monochrome`(Android 13 테마 아이콘)
- `android/.../mipmap-anydpi-v26/ic_launcher.xml` — adaptive icon 정의

## UI 디자인 시스템

앱 아이콘의 색·형태 언어(보라→인디고 그라디언트, 시안/핑크 글로우, 열린 문 마크)를
화면에도 그대로 쓴다. 새 화면을 만들 때는 아래 조각을 조합한다.

- [lib/ui/theme/app_theme.dart](lib/ui/theme/app_theme.dart) — `AppPalette` 와 `buildAppTheme()`.
  Scaffold 배경은 투명이므로 화면은 반드시 `AuroraBackground` 위에 얹어야 한다.
- [AuroraBackground](lib/ui/widgets/aurora_background.dart) — 빛덩이가 천천히 흐르는 배경.
  통화처럼 자원을 아껴야 할 때는 `animate: false` 로 멈춘다.
- [GlassCard · SectionLabel · StatusPill · GlowButton · CircleActionButton](lib/ui/widgets/glass.dart)
  — 유리 패널, 구획 제목, 상태 알약, 주 동작 버튼, 통화용 원형 버튼.
- [DoorMark](lib/ui/widgets/door_mark.dart) — 문은 아이콘 생성기가 만든
  `assets/icon/door_glyph.png` 를 얹고, 시그널 아크만 벡터로 그려 바깥으로 번지게 한다.
  아이콘을 다시 뽑으면 화면 로고도 같이 바뀐다.
  문 그림의 원본은 [Icons8 "Door"](https://icons8.com/icon/set/door/ios) 이다. 무료
  사용 조건이 출처 표기라 스토어 설명에 "Icons by Icons8" 를 둔다.
- [PulseAvatar](lib/ui/widgets/pulse_avatar.dart) — 통화 상대 아바타. 링이 퍼진다.
