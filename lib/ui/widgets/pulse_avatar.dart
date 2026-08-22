import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 통화 상대를 표시하는 원형 아바타. 신호가 퍼지듯 링이 밖으로 번진다.
class PulseAvatar extends StatefulWidget {
  const PulseAvatar({
    super.key,
    this.icon = Icons.doorbell,
    this.size = 116,
    this.color = AppPalette.cyan,
    this.animate = true,
  });

  final IconData icon;
  final double size;
  final Color color;

  /// 통화가 연결되면 링을 멈춰 화면을 차분하게 만든다.
  final bool animate;

  @override
  State<PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<PulseAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseAvatar oldWidget) {
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
    final outer = widget.size * 1.9;
    return RepaintBoundary(
      child: SizedBox(
        width: outer,
        height: outer,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.animate)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  size: Size.square(outer),
                  painter: _RingPainter(_controller.value, widget.color),
                ),
              ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppPalette.violet, AppPalette.indigo],
                ),
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.35),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                widget.icon,
                size: widget.size * 0.42,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final minRadius = size.width / 3.8;
    for (var i = 0; i < 3; i++) {
      final progress = (t + i / 3) % 1;
      final radius = minRadius + (size.width / 2 - minRadius) * progress;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - progress) * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.t != t;
}
