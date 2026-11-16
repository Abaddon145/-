import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import '../../../services/fsrs_service.dart';

class StudyActions extends StatefulWidget {
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
  State<StudyActions> createState() => _StudyActionsState();
}

class _StudyActionsState extends State<StudyActions> {
  StudyRating? _acked;

  Future<void> _rate(StudyRating rating) async {
    if (widget.busy) return;
    setState(() => _acked = rating);
    await Future<void>.delayed(AppMotion.duration(context, 120));
    if (!mounted) return;
    widget.onRate(rating);
    if (mounted) setState(() => _acked = null);
  }

  @override
  Widget build(BuildContext context) {
    final revealed = widget.revealed;
    final busy = widget.busy;
    final hold = widget.hold;
    final intervals = widget.intervals;
    final onReveal = widget.onReveal;
    return LayoutBuilder(
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
                        (StudyRating.again, '忘记', Icons.replay_rounded),
                        (StudyRating.hard, '困难', null),
                        (StudyRating.good, '认识', Icons.check_rounded),
                        (StudyRating.easy, '简单', null),
                      ])
                        SizedBox(
                          width:
                              (bounds.maxWidth - 8 * (columns - 1)) / columns,
                          height: height,
                          child: PressFeedback(
                            child: _rateButton(context, rating),
                          ),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _rateButton(
    BuildContext context,
    (StudyRating, String, IconData?) rating,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final interval = widget.intervals[rating.$1];
    final label = Text(
      interval ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final title = _acked == rating.$1
        ? const Icon(Icons.check, size: 18)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (rating.$3 != null) ...[
                Icon(rating.$3, size: 16),
                const SizedBox(width: 4),
              ],
              Flexible(child: Text(rating.$2, overflow: TextOverflow.ellipsis)),
            ],
          );
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [title, if (interval != null) label],
    );
    final onPressed = widget.busy ? null : () => _rate(rating.$1);
    if (rating.$1 == StudyRating.good) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: child,
      );
    }
    if (rating.$1 == StudyRating.easy) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: child,
      );
    }
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        backgroundColor: rating.$1 == StudyRating.again
            ? scheme.errorContainer
            : null,
        foregroundColor: rating.$1 == StudyRating.again
            ? scheme.onErrorContainer
            : null,
      ),
      child: child,
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
