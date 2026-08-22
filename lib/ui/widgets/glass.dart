import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 배경 오로라가 비쳐 보이는 반투명 패널.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.blur = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppPalette.glassStroke),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppPalette.glassFill, AppPalette.glassFillSoft],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 카드 안의 구획 제목. 대문자 자간을 넓혀 라벨처럼 읽히게 한다.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: AppPalette.cyan),
          const SizedBox(width: 8),
        ],
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: AppPalette.cyan,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

enum StatusTone { neutral, info, success, warning, danger }

extension on StatusTone {
  Color get color => switch (this) {
    StatusTone.neutral => Colors.white54,
    StatusTone.info => AppPalette.cyan,
    StatusTone.success => AppPalette.success,
    StatusTone.warning => AppPalette.warning,
    StatusTone.danger => AppPalette.danger,
  };
}

/// 상태 한 줄을 보여 주는 알약. 화면마다 제각각이던 배너를 이걸로 통일한다.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.tone,
    required this.message,
    this.icon,
    this.busy = false,
  });

  final StatusTone tone;
  final String message;
  final IconData? icon;

  /// 아이콘 대신 진행 표시를 돌린다.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = tone.color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: busy
                ? CircularProgressIndicator(strokeWidth: 2, color: color)
                : Icon(icon ?? Icons.info_outline, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 그라디언트와 광원을 가진 주 동작 버튼.
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.gradient = AppPalette.primaryGradient,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final LinearGradient gradient;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final glow = gradient.colors.last;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: enabled
            ? gradient
            : LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.06),
                ],
              ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: glow.withValues(alpha: 0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: 20,
                    color: enabled ? Colors.white : Colors.white38,
                  ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: enabled ? Colors.white : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 통화 화면의 원형 동작 버튼.
class CircleActionButton extends StatelessWidget {
  const CircleActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
    this.filled = true,
    this.size = 66,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  /// false 면 유리 표면에 색 테두리만 남긴다(보조 동작).
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : color.withValues(alpha: 0.14),
            border: Border.all(
              color: filled ? Colors.transparent : color.withValues(alpha: 0.5),
            ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Icon(
                icon,
                size: size * 0.42,
                color: filled ? Colors.white : color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }
}
