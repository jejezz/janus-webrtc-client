import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/participant.dart';

/// 참가자 한 명의 영상과 상태 배지를 그리는 타일.
class VideoTile extends StatelessWidget {
  const VideoTile({super.key, required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    final showVideo = participant.hasVideo && !participant.videoMuted;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black87,
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
                child: Icon(Icons.videocam_off, size: 40, color: Colors.white24),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
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
                  if (participant.audioMuted) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.mic_off, size: 16, color: Colors.redAccent),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
