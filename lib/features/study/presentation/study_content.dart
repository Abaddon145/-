import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_motion.dart';
import '../../../services/fsrs_service.dart';

class StudyActions extends StatelessWidget {
  const StudyActions({
    super.key,
    required this.revealed,
    required this.busy,
    required this.onReveal,
    required this.onRate,
    this.hold = false,
    this.intervals = const {},
  });
  final bool revealed, busy, hold;
  final VoidCallback onReveal;
  final ValueChanged<StudyRating> onRate;
  final Map<StudyRating, String> intervals;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scaled = MediaQuery.textScalerOf(context).scale(15);
      final columns = bounds.maxWidth < 340 || scaled > 20 ? 2 : 4;
      final hasIntervals = intervals.isNotEmpty;
      final height =
          math.max(52.0, scaled * 1.4 + 24) +
          (hasIntervals ? math.max(16.0, scaled * 0.8) : 0);
      final total = columns == 2 ? height * 2 + 8 : height;
      // Reserve the same space before and after revealing, so the card stays put.
      return SizedBox(
        height: total,
        child: Center(
          child: hold
              ? Text(
                  '先检查答案，再选择熟悉程度',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
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
                          child: _RatingButton(
                            label: rating.$2,
                            interval: intervals[rating.$1],
                            busy: busy,
                            style: _ratingStyle(context, rating.$1),
                            onPressed: () {
                              if (!AppMotion.reduced(context)) {
                                HapticFeedback.selectionClick().ignore();
                              }
                              onRate(rating.$1);
                            },
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

ButtonStyle _ratingStyle(BuildContext context, StudyRating rating) {
  final colors = Theme.of(context).colorScheme;
  final (background, foreground) = switch (rating) {
    StudyRating.again => (colors.errorContainer, colors.onErrorContainer),
    StudyRating.hard => (colors.tertiaryContainer, colors.onTertiaryContainer),
    StudyRating.good => (colors.primary, colors.onPrimary),
    StudyRating.easy => (colors.primaryContainer, colors.onPrimaryContainer),
  };
  return FilledButton.styleFrom(
    backgroundColor: background,
    foregroundColor: foreground,
    padding: const EdgeInsets.symmetric(horizontal: 4),
  );
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.interval,
    required this.busy,
    required this.style,
    required this.onPressed,
  });
  final String label;
  final String? interval;
  final bool busy;
  final ButtonStyle style;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spoken = interval == null ? '评为$label' : '评为$label，间隔 $interval';
    return Semantics(
      button: true,
      label: spoken,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: style,
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label),
              if (interval != null)
                Text(
                  interval!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: DefaultTextStyle.of(context).style.color,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
