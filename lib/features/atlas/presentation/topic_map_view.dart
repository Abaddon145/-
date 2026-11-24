import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';

class TopicMapPainter extends CustomPainter {
  const TopicMapPainter({
    required this.values,
    required this.color,
    required this.track,
  });
  final List<double> values;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final columns = 4;
    final rows = (values.length / columns).ceil();
    final cellW = size.width / columns;
    final cellH = size.height / rows;
    for (var index = 0; index < values.length; index++) {
      final column = index % columns;
      final row = index ~/ columns;
      final center = Offset(
        cellW * column + cellW / 2,
        cellH * row + cellH / 2,
      );
      final radius = (cellW < cellH ? cellW : cellH) * 0.28;
      canvas.drawCircle(center, radius, Paint()..color = track);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.5708,
        6.28318 * values[index].clamp(0, 1),
        true,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(TopicMapPainter oldDelegate) => true;
}

class TopicMapView extends StatelessWidget {
  const TopicMapView({super.key, required this.progress});
  final List<TopicProgress> progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 280,
          child: CustomPaint(
            painter: TopicMapPainter(
              values: [for (final item in progress) item.mastery],
              color: colors.primary,
              track: colors.surfaceContainerHighest,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        for (final item in progress)
          ListTile(
            title: Text(item.label),
            subtitle: Text(
              '已开始 ${item.started} · 已掌握 ${item.mastered} / ${item.total}',
            ),
          ),
      ],
    );
  }
}
