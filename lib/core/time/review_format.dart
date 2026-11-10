String formatReviewMoment(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final clock = now ?? DateTime.now();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (local.year != clock.year) {
    return '${local.year}年${local.month}月${local.day}日 $time';
  }
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(clock.year, clock.month, clock.day);
  final label = switch (day.difference(today).inDays) {
    0 => '今天',
    1 => '明天',
    -1 => '昨天',
    _ => '${local.month}月${local.day}日',
  };
  return '$label $time';
}
