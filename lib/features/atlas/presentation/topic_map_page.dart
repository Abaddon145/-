import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';
import 'topic_map_view.dart';

class TopicMapPage extends ConsumerWidget {
  const TopicMapPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(_topicProgressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('话题进度')),
      body: progress.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('暂时无法读取话题：$error')),
        data: (items) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('19 个话题的掌握度。已掌握指复习态且稳定度至少 21 天。'),
            const SizedBox(height: 12),
            TopicMapView(progress: items),
          ],
        ),
      ),
    );
  }
}

final _topicProgressProvider = FutureProvider.autoDispose<List<TopicProgress>>((
  ref,
) {
  return ref.watch(databaseProvider).loadTopicProgress();
});
