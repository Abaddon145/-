import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import '../domain/ai_models.dart';

Future<Set<String>?> chooseAiFields(
  BuildContext context, {
  required Map<String, String> values,
  required Map<String, String> existing,
  required Set<String> selected,
  required Set<String> recommended,
}) {
  final picks = {...selected};
  return showModalBottomSheet<Set<String>>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    sheetAnimationStyle: AppMotion.sheet(context),
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择要保存的内容',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭选择内容',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      picks.clear();
                      picks.addAll(recommended);
                    }),
                    child: const Text('选择缺失内容'),
                  ),
                  TextButton(
                    onPressed: () => setState(picks.clear),
                    child: const Text('清除选择'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final entry in values.entries)
                    if (entry.value.trim().isNotEmpty)
                      CheckboxListTile(
                        value: picks.contains(entry.key),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            picks.add(entry.key);
                          } else {
                            picks.remove(entry.key);
                          }
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(aiFieldLabels[entry.key]!),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              aiFieldMissing(entry.key, existing[entry.key])
                                  ? '当前缺失'
                                  : '已有内容，勾选后将更新',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            Text(
                              entry.value,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, picks),
                  child: Text('应用选择（${picks.length} 项）'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
