/// Target hidden by cloze practice. Shared by the queue and the card UI.
///
/// Splits on `/` (optional surrounding spaces) and uses the first piece that
/// contains Hangul. `love / 사랑` and `사랑 / 학교` both target `사랑`.
String clozeTarget(String korean) {
  final parts = korean
      .split(RegExp(r'\s*/\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return korean.trim();
  final hangul = RegExp('[가-힣ㄱ-ㅎㅏ-ㅣ]');
  for (final part in parts) {
    if (hangul.hasMatch(part)) return part;
  }
  return parts.first;
}

bool exampleContainsClozeTarget(String korean, String? example) {
  final target = clozeTarget(korean);
  return example != null && target.isNotEmpty && example.contains(target);
}
