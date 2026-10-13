import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cloud_sync_controller.dart';

class CloudSyncObserver extends ConsumerStatefulWidget {
  const CloudSyncObserver({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<CloudSyncObserver> createState() => _CloudSyncObserverState();
}

class _CloudSyncObserverState extends ConsumerState<CloudSyncObserver> with WidgetsBindingObserver {
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(cloudSyncProvider.notifier).setForeground(state == AppLifecycleState.resumed);
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    ref.watch(cloudSyncProvider);
    return widget.child;
  }
}
