import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 12키 다이얼 패드.
///
/// 모양은 이 앱의 언어로 그린다 — `CircleActionButton(filled: false)` 와 같은
/// 유리 표면에 시안 테두리.
///
/// 지우기는 여기 두지 않는다. 키패드를 접어도 지울 수 있어야 하므로 번호
/// 입력칸 오른쪽에 따로 있다(DialerScreen 참고).
///
/// 통화 중에는 같은 위젯을 DTMF 전송에 재사용한다.
class DialPad extends StatelessWidget {
  const DialPad({super.key, required this.onDigit, this.keySize = 64});

  final ValueChanged<String> onDigit;

  final double keySize;

  static const List<List<(String, String)>> _rows = [
    [('1', ''), ('2', 'ABC'), ('3', 'DEF')],
    [('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO')],
    [('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ')],
    [('*', ''), ('0', '+'), ('#', '')],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (digit, letters) in _rows[i]) _buildKey(digit, letters),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildKey(String digit, String letters) {
    return SizedBox(
      width: keySize,
      height: keySize,
      child: Material(
        color: AppPalette.glassFill,
        shape: CircleBorder(
          side: BorderSide(color: AppPalette.glassStroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onDigit(digit);
          },
          child: Semantics(
            button: true,
            label: digit,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  digit,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                if (letters.isNotEmpty)
                  Text(
                    letters,
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.2,
                      color: Colors.white38,
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
