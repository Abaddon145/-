import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/ai_models.dart';

/// This clock rebuilds only the status, preserving editors and list positions.
class AiRequestStatus extends StatefulWidget {
  const AiRequestStatus({super.key, required this.onCancel});
  final VoidCallback onCancel;
  @override
  State<AiRequestStatus> createState() => _AiRequestStatusState();
}

class _AiRequestStatusState extends State<AiRequestStatus> {
  final _clock = Stopwatch()..start();
  Timer? _timer;
  bool _cancelling = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          _cancelling ? '正在取消请求…' : '正在生成 · 已等待 ${_clock.elapsed.inSeconds} 秒',
        ),
        Text(
          _clock.elapsed.inSeconds >= 20
              ? '服务响应较慢，可以取消后继续背词。请求超时后会停止。'
              : '你可以滚动查看已有内容，或取消后继续背词。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          onPressed: _cancelling
              ? null
              : () {
                  setState(() => _cancelling = true);
                  widget.onCancel();
                },
          child: const Text('取消请求'),
        ),
      ],
    ),
  );
}

class AiErrorNotice extends StatefulWidget {
  const AiErrorNotice({super.key, required this.error, required this.onRetry});
  final AiException error;
  final VoidCallback? onRetry;
  @override
  State<AiErrorNotice> createState() => _AiErrorNoticeState();
}

class _AiErrorNoticeState extends State<AiErrorNotice> {
  Timer? _timer;
  late DateTime _retryAt;
  int get _remaining =>
      (_retryAt.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(
        0,
        300,
      );
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _retryAt = DateTime.now().add(
      Duration(seconds: widget.error.retryAfterSeconds ?? 0),
    );
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {});
        if (_remaining == 0) timer.cancel();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AiErrorNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.error, widget.error)) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    final colors = Theme.of(context).colorScheme;
    final cancelled = error.code == 'cancelled';
    return Card(
      color: cancelled ? colors.surfaceContainerHighest : colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.message,
              style: TextStyle(
                color: cancelled ? colors.onSurface : colors.onErrorContainer,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (error.canRetry)
                  TextButton(
                    onPressed: _remaining > 0 ? null : widget.onRetry,
                    child: Text(
                      _remaining > 0 ? '$_remaining 秒后可重试' : '重试本次请求',
                    ),
                  ),
                if (error.needsSettings)
                  TextButton(
                    onPressed: () {
                      final router = GoRouter.of(context);
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                      router.push('/settings/ai');
                    },
                    child: const Text('检查 AI 设置'),
                  ),
                if (error.code == 'insufficient_balance')
                  TextButton(
                    onPressed: () async {
                      final opened = await launchUrl(
                        Uri.parse('https://platform.deepseek.com/'),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '请在浏览器打开 platform.deepseek.com 检查 API 余额。',
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('打开 DeepSeek 平台'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
