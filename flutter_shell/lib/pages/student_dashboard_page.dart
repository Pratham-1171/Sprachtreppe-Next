import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import '../services/dashboard_service.dart';
import '../services/offline_sync_service.dart';
import '../services/progress_service.dart';
import 'notification_center_page.dart';

class StudentDashboardPage extends StatefulWidget {
  const StudentDashboardPage({super.key, required this.user});
  final AppUser user;

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  late final DashboardService _dashboardService;
  late Future<DashboardData> _future;
  late Future<ProgressStats> _progressFuture;
  late Future<DateTime?> _lastSyncFuture;
  late final OfflineSyncService _syncService;

  @override
  void initState() {
    super.initState();
    _dashboardService = DashboardService(Supabase.instance.client);
    _syncService = OfflineSyncService(Supabase.instance.client, widget.user.id);
    _load();
  }

  void _load() {
    _future = _dashboardService.load(widget.user.id);
    _progressFuture = ProgressService(widget.user.id).loadStats();
    _lastSyncFuture = _syncService.loadLastSyncAt();
  }

  Future<void> _openSyncCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationCenterPage(
          userId: widget.user.id,
          includeProgressSync: true,
        ),
      ),
    );
    if (mounted) {
      setState(() => _lastSyncFuture = _syncService.loadLastSyncAt());
    }
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait<Object>([_future, _progressFuture]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(error: snapshot.error, onRetry: _refresh);
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text('Welcome back, ${_firstName(widget.user.displayName)}',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('Keep your German progress moving.',
                  style: Theme.of(context).textTheme.bodyLarge),
              if (_dashboardService.lastLoadUsedCache) ...[
                const SizedBox(height: 10),
                const _OfflineDashboardNotice(),
              ],
              const SizedBox(height: 18),
              _StatsGrid(data: data),
              const SizedBox(height: 10),
              FutureBuilder<ProgressStats>(
                future: _progressFuture,
                builder: (context, progressSnapshot) {
                  final stats = progressSnapshot.data;
                  if (stats == null) return const SizedBox.shrink();
                  return _StudyProgressCard(stats: stats);
                },
              ),
              const SizedBox(height: 22),
              FutureBuilder<DateTime?>(
                future: _lastSyncFuture,
                builder: (context, syncSnapshot) {
                  if (syncSnapshot.connectionState == ConnectionState.waiting &&
                      !syncSnapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  if (!OfflineSyncService.isSyncDue(syncSnapshot.data)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: _SyncReminderCard(onSync: _openSyncCenter),
                  );
                },
              ),
              _SectionHeader(title: 'Your classes', count: data.classes.length),
              const SizedBox(height: 10),
              if (data.classes.isEmpty)
                const _EmptyCard(text: 'You are not enrolled in a class yet.')
              else
                ...data.classes.map((item) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                        title: Text(item.name),
                        subtitle: const Text('German learning class'),
                      ),
                    )),
              const SizedBox(height: 18),
              _SectionHeader(title: 'Pending assignments', count: data.pendingAssignments.length),
              const SizedBox(height: 10),
              if (data.pendingAssignments.isEmpty)
                const _EmptyCard(text: 'No pending assignments. Great job!')
              else
                ...data.pendingAssignments.map((item) => _AssignmentCard(item: item)),
              const SizedBox(height: 18),
              _SectionHeader(title: 'Announcements', count: data.recentAnnouncements.length),
              const SizedBox(height: 10),
              if (data.recentAnnouncements.isEmpty)
                const _EmptyCard(text: 'No recent announcements.')
              else
                ...data.recentAnnouncements.map((item) => _AnnouncementCard(item: item)),
            ],
          ),
        );
      },
    );
  }

  String _firstName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Classes', '${data.classes.length}', Icons.groups_outlined),
      ('Pending', '${data.pendingAssignments.length}', Icons.assignment_outlined),
      ('Completed', '${data.completedAssignments}', Icons.task_alt_outlined),
      ('Alerts', '${data.unreadNotifications}', Icons.notifications_none_outlined),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.65,
      ),
      itemBuilder: (context, index) {
        final card = cards[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(card.$3),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.$2, style: Theme.of(context).textTheme.titleLarge),
                      Text(card.$1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StudyProgressCard extends StatelessWidget {
  const _StudyProgressCard({required this.stats});

  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = stats.lastStudiedAt?.toLocal();
    final lastLabel = last == null
        ? 'Start a practice round to build your learning history.'
        : 'Last practice: ${last.day}/${last.month}/${last.year}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Study progress', style: theme.textTheme.titleLarge),
                ),
                const Icon(Icons.local_fire_department_outlined),
                const SizedBox(width: 4),
                Text('${stats.currentStreak}-day streak',
                    style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ProgressMetric(label: 'Questions', value: '${stats.totalQuestions}'),
                _ProgressMetric(label: 'Accuracy', value: '${stats.accuracyPercent}%'),
                _ProgressMetric(label: 'Rounds', value: '${stats.totalSessions}'),
                _ProgressMetric(label: 'Best streak', value: '${stats.bestStreak} days'),
              ],
            ),
            const SizedBox(height: 10),
            Text(lastLabel, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 3),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.item});
  final AssignmentSummary item;

  @override
  Widget build(BuildContext context) {
    final target = item.targetCount;
    final progress = target > 0 ? (item.done / target).clamp(0.0, 1.0) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(item.title, style: Theme.of(context).textTheme.titleMedium)),
                if (item.skill.isNotEmpty) Chip(label: Text(item.skill)),
              ],
            ),
            const SizedBox(height: 4),
            Text(item.className),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('${item.done} / ${item.targetCount} done'),
                const Spacer(),
                if (item.dueAt != null) Text(_dueLabel(item.dueAt!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dueLabel(DateTime due) {
    final local = due.toLocal();
    return 'Due ${local.day}/${local.month}';
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.item});
  final AnnouncementSummary item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        leading: Icon(item.pinned ? Icons.push_pin : Icons.campaign_outlined),
        title: Text(item.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(item.body, maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        Text('$count', style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Text(text)));
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            const Text('Could not load your dashboard.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text('$error', maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}


class _SyncReminderCard extends StatelessWidget {
  const _SyncReminderCard({required this.onSync});

  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_sync_outlined, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Weekly sync is due', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      const Text(
                        'Connect to the internet to send your saved study progress and receive feedback from your school.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSync,
                icon: const Icon(Icons.sync),
                label: const Text('Sync progress now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _OfflineDashboardNotice extends StatelessWidget {
  const _OfflineDashboardNotice();

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
                  'Offline view: showing the last saved dashboard. Connect to refresh classes, assignments and announcements.',
                ),
              ),
            ],
          ),
        ),
      );
}
