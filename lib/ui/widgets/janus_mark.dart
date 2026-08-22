import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 앱 아이콘의 통화 마크를 화면에서도 그대로 쓰는 위젯.
///
/// 말풍선은 아이콘 생성기가 만든 `assets/icon/call_glyph.png`(1024 좌표계)를 얹고,
/// 시그널 아크만 벡터로 그려 신호가 퍼지듯 밝아지게 한다. 좌표를 고칠 일이
/// 생기면 `tool/generate_app_icon.py` 와 아래 상수를 함께 맞춰야 한다.
class JanusMark extends StatefulWidget {
  const JanusMark({super.key, this.width = 120, this.animate = true});

  final double width;
  final bool animate;

  @override
  State<JanusMark> createState() => _JanusMarkState();
}

class _JanusMarkState extends State<JanusMark>
    with SingleTickerProviderStateMixin {
  static Future<ui.Image>? _glyphFuture;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  ui.Image? _glyph;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
    // 여러 화면에서 같은 이미지를 쓰므로 한 번만 디코딩한다.
    (_glyphFuture ??= _loadGlyph()).then((image) {
      if (mounted) setState(() => _glyph = image);
    });
  }

  static Future<ui.Image> _loadGlyph() async {
    final data = await rootBundle.load('assets/icon/call_glyph.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  @override
  void didUpdateWidget(covariant JanusMark oldWidget) {
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
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.width * _JanusMarkPainter.contentAspect,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) =>
              CustomPaint(painter: _JanusMarkPainter(_controller.value, _glyph)),
        ),
      ),
    );
  }
}

class _JanusMarkPainter extends CustomPainter {
  const _JanusMarkPainter(this.t, this.glyph);

  final double t;
  final ui.Image? glyph;

  // ── 아이콘 생성기와 공유하는 좌표 ──────────────────────────────────────────
  static const Offset _arcCenter = Offset(512, 500);
  static const double _arcSpanDegrees = 50;

  /// (반경, 두께, 기본 알파)
  static const List<(double, double, double)> _arcs = [
    (330, 26, 1.00),
    (400, 20, 0.62),
  ];

  /// 마크가 실제로 차지하는 영역.
  static const Rect content = Rect.fromLTRB(108, 145, 916, 865);
  static double get contentAspect => content.height / content.width;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / content.width,
      size.height / content.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - content.width * scale) / 2 - content.left * scale,
      (size.height - content.height * scale) / 2 - content.top * scale,
    );
    canvas.scale(scale);

    _paintArcs(canvas);
    _paintGlyph(canvas);

    canvas.restore();
  }

  void _paintArcs(Canvas canvas) {
    for (var i = 0; i < _arcs.length; i++) {
      final (radius, width, baseAlpha) = _arcs[i];
      // 안쪽에서 바깥으로 밝기가 번져 나가게 위상을 어긋나게 준다.
      final pulse = 0.5 + 0.5 * math.cos(2 * math.pi * (t - i * 0.25));
      final alpha = (baseAlpha * (0.55 + 0.45 * pulse)).clamp(0.0, 1.0);
      final rect = Rect.fromCircle(center: _arcCenter, radius: radius);
      const span = _arcSpanDegrees * math.pi / 180;

      for (final (start, color) in [
        (-span, AppPalette.cyan),
        (math.pi - span, AppPalette.pink),
      ]) {
        // 먼저 번지는 빛, 그 위에 선.
        canvas.drawArc(
          rect,
          start,
          span * 2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width * 1.6
            ..color = color.withValues(alpha: alpha * 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
        canvas.drawArc(
          rect,
          start,
          span * 2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width
            ..color = color.withValues(alpha: alpha),
        );
      }
    }
  }

  void _paintGlyph(Canvas canvas) {
    final image = glyph;
    if (image == null) return;

    // 말풍선 뒤 은은한 광원.
    final glowRect = Rect.fromCircle(center: const Offset(512, 500), radius: 300);
    canvas.drawCircle(
      const Offset(512, 500),
      280,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppPalette.violet.withValues(alpha: 0.55),
            AppPalette.violet.withValues(alpha: 0),
          ],
        ).createShader(glowRect),
    );

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, 1024, 1024),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_JanusMarkPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.glyph != glyph;
}
