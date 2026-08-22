import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 아이콘 배경과 같은 결의 그라디언트 위로 빛덩이가 천천히 흐르는 배경.
///
/// 모든 화면이 이 위에 얹히므로 Scaffold 는 투명하게 두고 이 위젯이 바닥을
/// 책임진다.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child, this.animate = true});

  final Widget child;

  /// 통화 중처럼 CPU 를 아껴야 할 때는 흐름을 멈춘다.
  final bool animate;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E1065), Color(0xFF1E1B4B), AppPalette.abyss],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _AuroraPainter(_controller.value),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter(this.t);

  /// 0..1 을 한 바퀴로 도는 진행도.
  final double t;

  /// (기준 위치, 반경 비율, 색, 세기, 공전 반경, 위상)
  static const List<(Offset, double, Color, double, double, double)> _blobs = [
    (Offset(0.86, 0.10), 0.55, AppPalette.cyan, 0.16, 0.07, 0.0),
    (Offset(0.10, 0.88), 0.52, AppPalette.pink, 0.14, 0.09, 0.35),
    (Offset(0.50, 0.30), 0.60, AppPalette.violet, 0.13, 0.06, 0.68),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.longestSide;
    for (final (base, radiusFactor, color, strength, orbit, phase) in _blobs) {
      final angle = (t + phase) * 2 * math.pi;
      final center = Offset(
        (base.dx + math.cos(angle) * orbit) * size.width,
        (base.dy + math.sin(angle * 0.8) * orbit) * size.height,
      );
      final radius = side * radiusFactor;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
        rect,
        Paint()
          // plus 로 겹쳐야 빛이 더해지는 느낌이 난다.
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: strength),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    // 가장자리를 눌러 가운데로 시선을 모은다.
    final full = Offset.zero & size;
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          radius: 0.85,
          colors: [
            AppPalette.abyss.withValues(alpha: 0),
            AppPalette.abyss.withValues(alpha: 0.72),
          ],
          stops: const [0.40, 1.0],
        ).createShader(full),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) => oldDelegate.t != t;
}
