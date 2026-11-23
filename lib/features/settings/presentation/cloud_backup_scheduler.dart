import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud_backup_service.dart';

/// Runs a due cloud backup when the app opens or returns to the foreground.
/// A closed PWA cannot wake itself, so the schedule is checked on resume.
class CloudBackupScheduler extends ConsumerStatefulWidget {
  const CloudBackupScheduler({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CloudBackupScheduler> createState() =>
      _CloudBackupSchedulerState();
}

class _CloudBackupSchedulerState extends ConsumerState<CloudBackupScheduler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  void _tick() {
    ref.read(cloudBackupServiceProvider).maybeScheduled();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
