import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/appearance_settings.dart';
import '../../study/domain/providers.dart';

class AppearancePage extends ConsumerStatefulWidget {
  const AppearancePage({super.key});

  @override
  ConsumerState<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends ConsumerState<AppearancePage> {
  bool _busy = false;

  Future<void> _selectStyle(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(databaseProvider).saveSetting(AppearanceSettings.styleKey, id);
      ref.invalidate(appearanceProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换风格失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseBackground() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (file == null) return;
      final bytes = Uint8List.fromList(await file.readAsBytes());
      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('请选择小于 2 MB 的图片');
      }
      await ref.read(databaseProvider).saveSetting(
        AppearanceSettings.backgroundKey,
        base64Encode(bytes),
      );
      ref.invalidate(appearanceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('背景已更新')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置背景失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeBackground() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(databaseProvider).saveSetting(
        AppearanceSettings.backgroundKey,
        null,
      );
      ref.invalidate(appearanceProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appearanceProvider);
    final selected = appearance.valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('外观风格')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text('打造你的学习空间', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              '选择配色，也可以使用自己的照片作为背景。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Text('预设风格', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: AppTheme.presets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.16,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final preset = AppTheme.presets[index];
                final active = selected?.styleId == preset.id;
                return InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _busy ? null : () => _selectStyle(preset.id),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [preset.start, preset.end],
                      ),
                      border: Border.all(
                        color: active ? preset.seed : preset.seed.withValues(alpha: 0.20),
                        width: active ? 2.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Icon(
                            active ? Icons.check_circle : Icons.circle_outlined,
                            color: preset.dark ? Colors.white : preset.seed,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: preset.dark ? Colors.white : const Color(0xFF26314A),
                          ),
                        ),
                        Text(
                          preset.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: preset.dark ? Colors.white70 : const Color(0xFF515E76),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            Text('自定义背景', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.wallpaper_rounded),
                    title: Text(selected?.hasBackground == true ? '已使用自定义背景' : '选择背景图片'),
                    subtitle: const Text('支持 JPG、PNG、WebP，最大 2 MB'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : _chooseBackground,
                  ),
                  if (selected?.hasBackground == true)
                    ListTile(
                      leading: const Icon(Icons.layers_clear_outlined),
                      title: const Text('移除自定义背景'),
                      onTap: _busy ? null : _removeBackground,
                    ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
