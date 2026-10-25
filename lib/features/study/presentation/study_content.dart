import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import '../../../services/fsrs_service.dart';

class StudyActions extends StatelessWidget {
  const StudyActions({
    super.key,
    required this.revealed,
    required this.busy,
    required this.onReveal,
    required this.onRate,
    this.quiz = false,
    this.onContinue,
  });
  final bool revealed, busy, quiz;
  final VoidCallback onReveal;
  final ValueChanged<StudyRating> onRate;
  final VoidCallback? onContinue;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scaled = MediaQuery.textScalerOf(context).scale(15);
      final columns = bounds.maxWidth < 340 || scaled > 20 ? 2 : 4;
      final height = math.max(52.0, scaled * 1.4 + 24);
      final total = columns == 2 ? height * 2 + 8 : height;
      // Reserve the same space before and after revealing, so the card stays put.
      return SizedBox(
        height: total,
        child: Center(
          child: quiz
              ? PressFeedback(
                  child: FilledButton(
                    onPressed: busy ? null : onContinue,
                    child: const Text('保存结果并继续'),
                  ),
                )
              : !revealed
              ? PressFeedback(
                  child: FilledButton(
                    onPressed: busy ? null : onReveal,
                    child: const Text('查看答案'),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final rating in const [
                      (StudyRating.again, '忘记'),
                      (StudyRating.hard, '困难'),
                      (StudyRating.good, '认识'),
                      (StudyRating.easy, '简单'),
                    ])
                      SizedBox(
                        width: (bounds.maxWidth - 8 * (columns - 1)) / columns,
                        height: height,
                        child: PressFeedback(
                          child: FilledButton.tonal(
                            onPressed: busy ? null : () => onRate(rating.$1),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                            child: Text(rating.$2),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      );
    },
  );
}

class StudyMeaning extends StatefulWidget {
  const StudyMeaning({super.key, required this.text, required this.style});
  final String text;
  final TextStyle? style;
  @override
  State<StudyMeaning> createState() => _StudyMeaningState();
}

class _StudyMeaningState extends State<StudyMeaning> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 4,
      )..layout(maxWidth: bounds.maxWidth);
      final long = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.text,
            style: widget.style,
            textAlign: TextAlign.center,
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (long)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起释义' : '展开完整释义'),
            ),
        ],
      );
    },
  );
}
