/// Shared by the library filter, AI selection and field acceptance defaults.
bool isMissingMeaning(String? value) {
  final text = (value ?? '').trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    '',
  );
  return text.isEmpty ||
      const {
        '（待补中文）',
        '(待补中文)',
        '待补中文',
        '暂无中文',
        '无中文',
        '暂无释义',
        '待补充',
        '未翻译',
        '待翻译',
        '-',
        '—',
        'n/a',
        '原表未提供中文释义',
        '原表未提供中文',
        '未提供中文释义',
      }.contains(text);
}
