import 'package:flutter/material.dart';

/// 앱 아이콘(말풍선 + 시그널 아크)에서 그대로 가져온 색.
///
/// 값이 바뀌면 `tool/generate_app_icon.py` 의 팔레트도 같이 맞춰야 아이콘과
/// 화면이 따로 놀지 않는다.
abstract final class AppPalette {
  static const Color violet = Color(0xFF8B5CF6);
  static const Color indigo = Color(0xFF4F46E5);
  static const Color abyss = Color(0xFF0C122B);
  static const Color cyan = Color(0xFF67E8F9);
  static const Color pink = Color(0xFFF9A8D4);

  /// 실루엣의 밝은 쪽/어두운 쪽. 로고와 본문 보조 텍스트에 쓴다.
  static const Color faceHigh = Color(0xFFFFFFFF);
  static const Color faceLow = Color(0xFFA5B4FC);
  static const Color mist = Color(0xFFC7D2FE);

  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFF6B81);

  /// 유리판 표면과 테두리.
  static const Color glassFill = Color(0x14FFFFFF);
  static const Color glassFillSoft = Color(0x08FFFFFF);
  static const Color glassStroke = Color(0x26FFFFFF);

  /// 주 동작 버튼(발신·등록)에 쓰는 그라디언트.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  );

  /// 통화 연결처럼 "살아 있는" 동작에 쓰는 그라디언트.
  static const LinearGradient liveGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF10B981), Color(0xFF22D3EE)],
  );

  static const LinearGradient dangerGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFF43F5E), Color(0xFFFB7185)],
  );
}

/// 아이콘과 같은 언어를 쓰는 다크 테마.
ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppPalette.indigo,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AppPalette.violet,
        secondary: AppPalette.cyan,
        surface: AppPalette.abyss,
        error: AppPalette.danger,
      );

  const radius = BorderRadius.all(Radius.circular(16));

  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 배경은 AuroraBackground 가 그리므로 Scaffold 는 비워 둔다.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: AppPalette.abyss,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppPalette.glassFillSoft,
      border: border(AppPalette.glassStroke),
      enabledBorder: border(AppPalette.glassStroke),
      focusedBorder: border(AppPalette.cyan, 1.4),
      errorBorder: border(AppPalette.danger),
      focusedErrorBorder: border(AppPalette.danger, 1.4),
      labelStyle: const TextStyle(color: AppPalette.mist),
      floatingLabelStyle: const TextStyle(color: AppPalette.cyan),
      helperStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
      helperMaxLines: 2,
      errorStyle: const TextStyle(color: AppPalette.danger, fontSize: 11.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.mist,
        side: const BorderSide(color: AppPalette.glassStroke),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Colors.white12, space: 32),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppPalette.cyan,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF1E1B4B),
      contentTextStyle: TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    textTheme: const TextTheme(
      bodySmall: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
    ).apply(bodyColor: Colors.white, displayColor: Colors.white),
  );
}
