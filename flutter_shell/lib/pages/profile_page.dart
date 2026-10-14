import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/offline_sync_service.dart';
import '../services/progress_service.dart';
import 'notification_center_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.user, required this.onSignOut});

  final AppUser user;
  final VoidCallback onSignOut;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final AuthService _authService;
  Future<ProgressStats>? _progressFuture;
  Future<DateTime?>? _lastSyncFuture;
  bool _resettingPassword = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(Supabase.instance.client);
    _loadLocalState();
  }

  void _loadLocalState() {
    if (widget.user.role != AppRole.student) return;
    _progressFuture = ProgressService(widget.user.id).loadStats();
    _lastSyncFuture = OfflineSyncService(
      Supabase.instance.client,
      widget.user.id,
    ).loadLastSyncAt();
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationCenterPage(
          userId: widget.user.id,
          includeProgressSync: widget.user.role == AppRole.student,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _progressFuture = ProgressService(widget.user.id).loadStats();
        _lastSyncFuture = OfflineSyncService(
          Supabase.instance.client,
          widget.user.id,
        ).loadLastSyncAt();
      });
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = Supabase.instance.client.auth.currentUser?.email?.trim();
    if (email == null || email.isEmpty) {
      _message('No email address is available for this signed-in account.', error: true);
      return;
    }

    setState(() => _resettingPassword = true);
    try {
      await _authService.sendPasswordReset(email);
      if (mounted) _message('If the account exists, a password reset email has been sent.');
    } on AuthException catch (error) {
      if (mounted) _message(error.message, error: true);
    } catch (_) {
      if (mounted) {
        _message('Could not send the reset email. Connect to the internet and try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _resettingPassword = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authUser = Supabase.instance.client.auth.currentUser;
    final email = authUser?.email?.trim();
    final name = widget.user.displayName.trim().isEmpty ? 'Sprachtreppe learner' : widget.user.displayName.trim();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('Your profile', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 5),
        Text('Account details and learning data stored on this device.', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(name.substring(0, 1).toUpperCase(), style: theme.textTheme.titleLarge),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(email?.isNotEmpty == true ? email! : 'Email unavailable offline'),
                      const SizedBox(height: 8),
                      Chip(
                        avatar: Icon(_roleIcon(widget.user.role), size: 18),
                        label: Text(widget.user.role.label),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Your password is never stored by this screen.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.user.role == AppRole.student) ...[
          const SizedBox(height: 16),
          if (_progressFuture != null)
            FutureBuilder<ProgressStats>(
              future: _progressFuture,
              builder: (context, snapshot) {
                final stats = snapshot.data;
                if (stats == null) {
                  if (snapshot.hasError) {
                    return const _ProfileInfoCard(
                      icon: Icons.school_outlined,
                      title: 'Local study progress',
                      body: 'Could not read the saved progress on this device.',
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _LocalProgressCard(stats: stats);
              },
            ),
          if (_lastSyncFuture != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<DateTime?>(
              future: _lastSyncFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const SizedBox.shrink();
                }
                return _SyncStatusCard(
                  lastSyncAt: snapshot.data,
                  onSync: _openNotifications,
                );
              },
            ),
          ],
        ],
        const SizedBox(height: 18),
        Text('Account security', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reset your password by email. You need an internet connection to request a reset link.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _resettingPassword || email?.isNotEmpty != true
                        ? null
                        : _sendPasswordReset,
                    icon: _resettingPassword
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_reset_outlined),
                    label: Text(_resettingPassword ? 'Sending reset email…' : 'Send password reset email'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: widget.onSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalProgressCard extends StatelessWidget {
  const _LocalProgressCard({required this.stats});

  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Local study progress', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Stat(label: 'Questions', value: '${stats.totalQuestions}')),
                Expanded(child: _Stat(label: 'Accuracy', value: '${stats.accuracyPercent}%')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Stat(label: 'Study rounds', value: '${stats.totalSessions}')),
                Expanded(child: _Stat(label: 'Best streak', value: '${stats.bestStreak} days')),
              ],
            ),
            if (stats.lastStudiedAt != null) ...[
              const SizedBox(height: 10),
              Text(
                'Last studied: ${_dateLabel(stats.lastStudiedAt)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({required this.lastSyncAt, required this.onSync});

  final DateTime? lastSyncAt;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final due = OfflineSyncService.isSyncDue(lastSyncAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('School sync', style: Theme.of(context).textTheme.titleMedium),
                ),
                Icon(
                  due ? Icons.schedule : Icons.check_circle_outline,
                  color: due ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              lastSyncAt == null
                  ? 'Progress has not been synced from this device yet.'
                  : 'Last synced: ${_dateLabel(lastSyncAt)}',
            ),
            if (due) ...[
              const SizedBox(height: 5),
              const Text('Sync at least once every 7 days so your school can receive your latest progress.'),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSync,
                icon: const Icon(Icons.sync),
                label: const Text('Open sync center'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(body),
        ),
      );
}

IconData _roleIcon(AppRole role) => switch (role) {
      AppRole.student => Icons.school_outlined,
      AppRole.teacher => Icons.co_present_outlined,
      AppRole.admin => Icons.admin_panel_settings_outlined,
    };

String _dateLabel(DateTime? value) {
  if (value == null) return 'Date unavailable';
  final date = value.toLocal();
  return '${date.day}/${date.month}/${date.year}';
}
