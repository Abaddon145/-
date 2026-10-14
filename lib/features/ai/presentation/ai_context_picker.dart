import 'package:flutter/material.dart';
import '../domain/ai_models.dart';

Future<String?> chooseAiContext(BuildContext context, String initial) async {
  final custom = TextEditingController(
    text: aiContexts.contains(initial) ? '' : initial,
  );
  var selected = aiContexts.contains(initial) ? initial : '自定义语境';
  String? error;
  final route = DialogRoute<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('选择 AI 语境'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  items: [
                    for (final value in aiContexts)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (v) => setState(() => selected = v!),
                ),
                if (selected == '自定义语境')
                  TextField(
                    controller: custom,
                    maxLength: 600,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: '工作场景、领域或上下文',
                      errorText: error,
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('仅发送这个词及必要语境。生成内容需要你核对后保存。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = selected == '自定义语境' ? custom.text.trim() : selected;
              if (text.isEmpty) {
                setState(() => error = '请填写语境');
                return;
              }
              Navigator.pop(ctx, text);
            },
            child: const Text('使用此语境'),
          ),
        ],
      ),
    ),
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;
  custom.dispose();
  return result;
}
