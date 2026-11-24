import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ShareCardData {
  const ShareCardData.word({
    required this.headword,
    required this.meaning,
    this.ipa = '',
    this.example = '',
    this.cefr = '',
    this.topic = '',
  }) : scoreLine = '',
       detailLine = '';

  const ShareCardData.session({
    required this.scoreLine,
    required this.detailLine,
  }) : headword = '本轮学习',
       meaning = '',
       ipa = '',
       example = '',
       cefr = '',
       topic = '';

  final String headword;
  final String meaning;
  final String ipa;
  final String example;
  final String cefr;
  final String topic;
  final String scoreLine;
  final String detailLine;

  bool get isSession => scoreLine.isNotEmpty;
}

class ShareCardPainter extends CustomPainter {
  const ShareCardPainter(this.data);
  final ShareCardData data;

  @override
  void paint(Canvas canvas, Size size) {
    final paper = Paint()..color = const Color(0xFFF6F1E7);
    final ink = const Color(0xFF1C2430);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(28)),
      paper,
    );
    final border = Paint()
      ..color = const Color(0xFF8C5A3C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Offset(18, 18) & Size(size.width - 36, size.height - 36),
        const Radius.circular(18),
      ),
      border,
    );
    _text(canvas, '词忆', Offset(48, 48), 22, ink, FontWeight.w700);
    if (data.isSession) {
      _text(canvas, data.headword, Offset(48, 140), 42, ink, FontWeight.w700);
      _text(
        canvas,
        data.scoreLine,
        Offset(48, 230),
        28,
        const Color(0xFF8C5A3C),
        FontWeight.w600,
      );
      _text(canvas, data.detailLine, Offset(48, 290), 22, ink, FontWeight.w400);
    } else {
      _text(canvas, data.headword, Offset(48, 130), 48, ink, FontWeight.w700);
      if (data.ipa.isNotEmpty) {
        _text(
          canvas,
          data.ipa,
          Offset(48, 200),
          22,
          const Color(0xFF5C6570),
          FontWeight.w400,
        );
      }
      _text(canvas, data.meaning, Offset(48, 250), 26, ink, FontWeight.w500);
      if (data.example.isNotEmpty) {
        _text(
          canvas,
          data.example,
          Offset(48, 330),
          20,
          const Color(0xFF3E4650),
          FontWeight.w400,
          width: size.width - 96,
        );
      }
      final tags = [
        if (data.cefr.isNotEmpty) data.cefr,
        if (data.topic.isNotEmpty) data.topic,
      ].join(' · ');
      if (tags.isNotEmpty) {
        _text(
          canvas,
          tags,
          Offset(48, size.height - 120),
          18,
          const Color(0xFF8C5A3C),
          FontWeight.w600,
        );
      }
    }
    _text(
      canvas,
      '本机学习记录',
      Offset(48, size.height - 64),
      16,
      const Color(0xFF6A6258),
      FontWeight.w400,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset offset,
    double size,
    Color color,
    FontWeight weight, {
    double width = 620,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          height: 1.35,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(ShareCardPainter oldDelegate) => oldDelegate.data != data;
}

Future<Uint8List> renderShareCard(ShareCardData data) async {
  const width = 720.0;
  const height = 960.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  ShareCardPainter(data).paint(canvas, const Size(width, height));
  final image = await recorder.endRecording().toImage(
    width.round(),
    height.round(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
