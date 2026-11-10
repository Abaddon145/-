import '../../../core/database/app_database.dart';

class EmptyQueueCopy {
  const EmptyQueueCopy({required this.title, required this.body});
  final String title;
  final String body;
}

EmptyQueueCopy emptyQueueCopy(EmptyQueueKind kind, SessionOptions options) {
  switch (kind) {
    case EmptyQueueKind.roundComplete:
      return const EmptyQueueCopy(
        title: '本轮已练完',
        body: '这一轮的数量已经完成。可以再开一轮，或回到每日计划。',
      );
    case EmptyQueueKind.dailyPlanDone:
      return const EmptyQueueCopy(
        title: '今日计划已完成',
        body: '今天的新词和复习额度都已完成。还可以再学一轮，或去统计看看进度。',
      );
    case EmptyQueueKind.libraryEmpty:
      return const EmptyQueueCopy(
        title: '还没有可学习的词',
        body: '词库里还没有单词。先录入一个，或导入 Excel 词表。',
      );
    case EmptyQueueKind.filteredEmpty:
      return const EmptyQueueCopy(
        title: '当前范围里没有可练的词',
        body: '收藏、错词、词书、词性或场景把范围缩空了。熟词和已暂停的词也不会出现。放宽条件后再开始。',
      );
    case EmptyQueueKind.modeNeedsContent:
      return EmptyQueueCopy(
        title: '当前模式下没有可练的词',
        body: options.mode == PracticeMode.forms
            ? '词形练习需要词条详情里已经保存的活用表。可以去词库补活用表，或换成翻卡、拼写。'
            : '例句填空只使用含有原词的例句。可以去词库补例句，或换成别的练习方式。',
      );
    case EmptyQueueKind.nothingLeft:
      return EmptyQueueCopy(
        title: options.daily ? '现在没有可练的词' : '这一轮没有更多可练的词',
        body: _nothingLeftBody(options),
      );
  }
}

String _nothingLeftBody(SessionOptions options) {
  if (options.mode == PracticeMode.cloze) {
    return '填空还要求例句里出现原词。可以改范围，或先去词库把例句补完整。';
  }
  if (options.mode == PracticeMode.forms) {
    return '词形练习只抽已保存的活用表。可以改范围，或先去词库补活用。';
  }
  if (options.queue == QueueKind.reviews) {
    return '当前范围里没有到期的复习。可以改成混合学习，或明天再来。';
  }
  if (options.queue == QueueKind.newWords) {
    return '当前范围里没有未学习的新词。可以改成复习，或去词库添加单词。';
  }
  if (options.daily) {
    return '今日额度还没用完，但现在没有可学的新词，也没有到期复习。可以去词库补充，或稍后再来。';
  }
  return '没有到期复习，也没有还能学的新词。可以调整范围，或先去词库看看。';
}
