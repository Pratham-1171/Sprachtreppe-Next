import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/offline_sync_service.dart';
import 'notification_center_page.dart';

/// Keeps the offline learning area available for one week after each successful
/// sync. Server access is still controlled by Supabase Auth and RLS.
class WeeklySyncGate extends StatefulWidget {
  const WeeklySyncGate({
    super.key,
    required this.userId,
    required this.child,
  });

  final String userId;
  final Widget child;

  @override
  State<WeeklySyncGate> createState() => _WeeklySyncGateState();
}

class _WeeklySyncGateState extends State<WeeklySyncGate> with WidgetsBindingObserver {
  late OfflineSyncService _syncService;
  late Future<DateTime?> _lastSyncFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncService = OfflineSyncService(Supabase.instance.client, widget.userId);
    _reload();
  }

  @override
  void didUpdateWidget(covariant WeeklySyncGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _syncService = OfflineSyncService(Supabase.instance.client, widget.userId);
    }
    // The parent rebuilds when the student changes tabs. Refresh so a sync done
    // from Profile or Notifications unlocks both Learn and Practice.
    _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_reload);
    }
  }

  void _reload() {
    _lastSyncFuture = _syncService.loadLastSyncAt();
  }

  Future<void> _openSyncCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationCenterPage(
          userId: widget.userId,
          includeProgressSync: true,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DateTime?>(
      future: _lastSyncFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final syncDue = snapshot.hasError || OfflineSyncService.isSyncDue(snapshot.data);
        if (!syncDue) return widget.child;

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_sync_outlined,
                        size: 52,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Weekly sync required',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.hasError
                            ? 'The saved sync status could not be checked. Open the sync center, connect to the internet and try again.'
                            : 'To keep school progress up to date, connect and sync at least once every 7 days. Your saved learning will unlock after a successful sync.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _openSyncCenter,
                          icon: const Icon(Icons.sync),
                          label: const Text('Connect and sync'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your saved practice history remains on this device while you are offline.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
