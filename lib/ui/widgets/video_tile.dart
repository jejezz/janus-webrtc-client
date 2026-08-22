import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/participant.dart';
import '../theme/app_theme.dart';

/// 참가자 한 명의 영상과 상태 배지를 그리는 타일.
class VideoTile extends StatelessWidget {
  const VideoTile({super.key, required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    final showVideo = participant.hasVideo && !participant.videoMuted;
    // 내 화면은 테두리 색으로 구분해 준다.
    final accent = participant.isLocal
        ? AppPalette.cyan.withValues(alpha: 0.55)
        : AppPalette.glassStroke;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: ColoredBox(
          color: const Color(0xFF0A0F22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showVideo)
                RTCVideoView(
                  participant.renderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  // 로컬 프리뷰만 좌우 반전해야 거울처럼 보인다.
                  mirror: participant.isLocal,
                )
              else
                const Center(
                  child: Icon(
                    Icons.videocam_off,
                    size: 40,
                    color: Colors.white24,
                  ),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Row(
                  children: [
                    Flexible(child: _nameChip()),
                    if (participant.audioMuted) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.mic_off,
                        size: 16,
                        color: AppPalette.danger,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameChip() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            participant.isLocal
                ? '${participant.displayName ?? '나'} (나)'
                : participant.displayName ?? participant.id,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
