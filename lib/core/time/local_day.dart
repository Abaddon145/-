import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

DateTime localDay(DateTime value) => DateTime(value.year, value.month, value.day);

final localDayProvider = StateProvider<DateTime>((ref) => localDay(DateTime.now()));

/// Keeps cached daily views current across midnight and app suspension.
class LocalDayObserver extends ConsumerStatefulWidget {
  const LocalDayObserver({super.key, required this.child, this.now});
  final Widget child;
  final DateTime Function()? now;

  @override
  ConsumerState<LocalDayObserver> createState() => _LocalDayObserverState();
}

class _LocalDayObserverState extends ConsumerState<LocalDayObserver>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = widget.now?.call() ?? DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(tomorrow.difference(now), _checkDay);
  }

  void _checkDay() {
    if (!mounted) return;
    final today = localDay(widget.now?.call() ?? DateTime.now());
    if (ref.read(localDayProvider) != today) {
      ref.read(localDayProvider.notifier).state = today;
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkDay();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
