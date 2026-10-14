import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../services/offline_sync_service.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({
    super.key,
    required this.userId,
    this.includeProgressSync = false,
  });

  final String userId;
  final bool includeProgressSync;

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  late final NotificationService _notifications;
  late final OfflineSyncService _sync;
  late Future<List<AppNotification>> _notificationFuture;
  late Future<DateTime?> _lastSyncFuture;
  final Set<int> _markingRead = {};
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _notifications = NotificationService(Supabase.instance.client, widget.userId);
    _sync = OfflineSyncService(Supabase.instance.client, widget.userId);
    _reload();
  }

  void _reload() {
    _notificationFuture = _notifications.load();
    _lastSyncFuture = _sync.loadLastSyncAt();
  }

  Future<void> _refresh() async {
    setState(_reload);
    try {
      await Future.wait([_notificationFuture, _lastSyncFuture]);
    } catch (_) {
      // The page renders separate retryable content for server and sync status.
    }
  }

  Future<void> _markRead(AppNotification notification) async {
    if (notification.isRead || _markingRead.contains(notification.id)) return;
    setState(() => _markingRead.add(notification.id));
    try {
      await _notifications.markRead(notification.id);
      if (!mounted) return;
      setState(() => _notificationFuture = _notifications.load());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark the notification as read. Retry when online.')),
      );
    } finally {
      if (mounted) setState(() => _markingRead.remove(notification.id));
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await _sync.syncNow();
      if (!mounted) return;

      setState(() {
        _lastSyncFuture = Future<DateTime?>.value(result.syncedAt);
        _notificationFuture = _notifications.load();
      });

      if (result.feedback.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Feedback from your administrator'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final feedback in result.feedback)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pretty(feedback.status),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (feedback.rating != null) ...[
                              const SizedBox(height: 4),
                              Text('Rating: ${feedback.rating}/5'),
                            ],
                            if (feedback.note?.trim().isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              Text(feedback.note!),
                            ],
                            if (feedback.reviewedAt != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Reviewed ${_dateLabel(feedback.reviewedAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        try {
          await _sync.acknowledgeFeedback(result.feedback.map((item) => item.id));
        } catch (_) {
          // Feedback remains unread on the server and will be returned at the next sync.
        }
      }

      if (!mounted) return;
      final assignmentMessage = result.assignmentProgressCount == 0
          ? ''
          : ' · ${result.assignmentProgressCount} assignment progress item(s)';
      final writtenMessage = result.writtenSubmissionCount == 0
          ? ''
          : ' · ${result.writtenSubmissionCount} written response(s)';
      final message = 'Synced ${result.sessionCount} saved sessions · '
          '${result.totalQuestions} questions · ${result.accuracyPercent}% accuracy'
          '$assignmentMessage$writtenMessage.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      var message = error.toString().replaceFirst('Exception: ', '');
      if (message.length > 180) message = '${message.substring(0, 177)}…';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $message'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AppNotification>>(
          future: _notificationFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: 260),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            final notifications = snapshot.data;
            final unread = notifications?.where((item) => !item.isRead).length ?? 0;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                if (widget.includeProgressSync) ...[
                  _SyncCard(
                    lastSyncFuture: _lastSyncFuture,
                    syncing: _syncing,
                    onSync: _syncNow,
                  ),
                  const SizedBox(height: 18),
                ],
                if (_notifications.lastLoadUsedCache) ...[
                  const _OfflineInboxNotice(),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text('Your inbox', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (notifications != null)
                      Chip(
                        label: Text('$unread unread'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snapshot.hasError)
                  _LoadError(
                    message: 'Could not load notifications. Check your connection and retry.',
                    onRetry: _refresh,
                  )
                else if (notifications == null || notifications.isEmpty)
                  const _EmptyInbox()
                else
                  for (final notification in notifications)
                    _NotificationCard(
                      notification: notification,
                      busy: _markingRead.contains(notification.id),
                      onMarkRead: () => _markRead(notification),
                    ),
                const SizedBox(height: 8),
                Text(
                  'Notifications are private to your signed-in account.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.lastSyncFuture,
    required this.syncing,
    required this.onSync,
  });

  final Future<DateTime?> lastSyncFuture;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_outlined, color: Theme.of(context).colorScheme.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Offline progress sync', style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Send locally saved practice history to your school and receive reviewed feedback.'),
            const SizedBox(height: 10),
            FutureBuilder<DateTime?>(
              future: lastSyncFuture,
              builder: (context, snapshot) {
                final last = snapshot.data;
                final due = OfflineSyncService.isSyncDue(last);
                final text = last == null
                    ? 'This device has not synced progress yet.'
                    : 'Last synced: ${_dateLabel(last)}';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: Theme.of(context).textTheme.bodySmall),
                    if (due) ...[
                      const SizedBox(height: 4),
                      Text(
                        'A sync is due. Connect to the internet and sync at least once every 7 days.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: syncing ? null : onSync,
                icon: syncing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(syncing ? 'Syncing progress…' : 'Sync now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.busy,
    required this.onMarkRead,
  });

  final AppNotification notification;
  final bool busy;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: notification.isRead
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primaryContainer,
                  child: Icon(
                    _kindIcon(notification.kind),
                    color: notification.isRead
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(notification.title, style: theme.textTheme.titleMedium),
                      if (notification.createdAt != null) ...[
                        const SizedBox(height: 3),
                        Text(_dateLabel(notification.createdAt), style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                if (!notification.isRead)
                  Text(
                    'New',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            if (notification.body.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(notification.body),
            ],
            if (!notification.isRead) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : onMarkRead,
                  child: Text(busy ? 'Saving…' : 'Mark as read'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.notifications_none_outlined, size: 40),
              SizedBox(height: 8),
              Text('You’re all caught up.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.cloud_off_outlined, size: 32),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}

IconData _kindIcon(String kind) => switch (kind) {
      'assignment_submission' => Icons.assignment_turned_in_outlined,
      'student_submission' => Icons.task_alt_outlined,
      'teacher_assignment' => Icons.co_present_outlined,
      'announcement' => Icons.campaign_outlined,
      _ => Icons.notifications_outlined,
    };

String _dateLabel(DateTime? value) {
  if (value == null) return 'Date unavailable';
  final date = value.toLocal();
  return '${date.day}/${date.month}/${date.year}';
}

String _pretty(String value) {
  if (value.trim().isEmpty) return 'Feedback';
  return value.split('_').map((part) => part.isEmpty
      ? part
      : '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}').join(' ');
}


class _OfflineInboxNotice extends StatelessWidget {
  const _OfflineInboxNotice();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.wifi_off_outlined),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Offline view: these are your last saved notifications. Connect to refresh the inbox or mark items as read.',
                ),
              ),
            ],
          ),
        ),
      );
}
