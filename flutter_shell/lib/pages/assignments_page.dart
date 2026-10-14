import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student_assignment.dart';
import '../services/assignment_service.dart';
import 'practice_page.dart';

class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({super.key, required this.userId});
  final String userId;

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  late final AssignmentService _service;
  late Future<List<StudentAssignment>> _future;
  String _filter = 'To do';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _service = AssignmentService(Supabase.instance.client);
    _load();
  }

  void _load() => _future = _service.loadForStudent(widget.userId);

  Future<void> _refresh() async {
    setState(_load);
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _open(StudentAssignment item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AssignmentDetailPage(userId: widget.userId, assignment: item),
      ),
    );
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<StudentAssignment>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _LoadError(onRetry: _refresh);

        final items = snapshot.data ?? const <StudentAssignment>[];
        final pending = items.where((item) => !item.isCompleted).length;
        final completed = items.length - pending;
        final search = _search.trim().toLowerCase();
        final visible = items.where((item) {
          final statusMatches = _filter == 'All' ||
              (_filter == 'To do' && !item.isCompleted) ||
              (_filter == 'Done' && item.isCompleted);
          final text = [
            item.title, item.instructions, item.kind, item.skill, item.className ?? '',
          ].join(' ').toLowerCase();
          return statusMatches && (search.isEmpty || text.contains(search));
        }).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text('Assignments', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text('Tasks, deadlines and completion status.', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _CountTile(label: 'To do', count: pending)),
                const SizedBox(width: 8),
                Expanded(child: _CountTile(label: 'Done', count: completed)),
                const SizedBox(width: 8),
                Expanded(child: _CountTile(label: 'All', count: items.length)),
              ]),
              const SizedBox(height: 14),
              TextField(
                onChanged: (value) => setState(() => _search = value),
                decoration: const InputDecoration(
                  labelText: 'Search assignments',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'All', label: Text('All')),
                  ButtonSegment(value: 'To do', label: Text('To do')),
                  ButtonSegment(value: 'Done', label: Text('Done')),
                ],
                selected: {_filter},
                onSelectionChanged: (value) => setState(() => _filter = value.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 10),
              if (visible.isEmpty)
                Card(child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(children: [
                    const Icon(Icons.assignment_outlined, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      items.isEmpty
                          ? 'No assignments have been assigned to you yet.'
                          : 'No assignments match these filters.',
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ))
              else
                for (final item in visible)
                  _AssignmentCard(item: item, onTap: () => _open(item)),
            ],
          ),
        );
      },
    );
  }
}

class AssignmentDetailPage extends StatefulWidget {
  const AssignmentDetailPage({
    super.key,
    required this.userId,
    required this.assignment,
  });

  final String userId;
  final StudentAssignment assignment;

  @override
  State<AssignmentDetailPage> createState() => _AssignmentDetailPageState();
}

class _AssignmentDetailPageState extends State<AssignmentDetailPage> {
  late final AssignmentService _service;
  late StudentAssignment _item;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _service = AssignmentService(Supabase.instance.client);
    _item = widget.assignment;
  }

  Future<void> _refreshItem() async {
    setState(() => _refreshing = true);
    try {
      final items = await _service.loadForStudent(widget.userId);
      final matches = items.where((item) => item.id == _item.id);
      if (matches.isNotEmpty && mounted) setState(() => _item = matches.first);
    } catch (_) {
      // Retain the last server-confirmed values when offline.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _startPractice() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Assignment practice')),
          body: PracticePage(
            userId: widget.userId,
            assignmentId: _item.id,
            assignmentTitle: _item.title,
            assignmentTargetCount: _item.targetCount,
            assignmentDone: _item.done,
            assignmentCorrect: _item.correct,
            assignmentSkill: _item.skill,
          ),
        ),
      ),
    );
    if (mounted) await _refreshItem();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final theme = Theme.of(context);
    final dueLabel = item.dueAt == null ? 'No deadline' : _dateLabel(item.dueAt!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignment details'),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : _refreshItem,
            tooltip: 'Refresh progress',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(item.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Chip(label: Text(_titleCase(item.kind))),
            if (item.skill.isNotEmpty) Chip(label: Text(_titleCase(item.skill))),
            if (item.className?.isNotEmpty == true)
              Chip(avatar: const Icon(Icons.groups_outlined, size: 18), label: Text(item.className!)),
          ]),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Instructions', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(item.instructions.trim().isEmpty
                  ? 'No extra instructions were provided.'
                  : item.instructions),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.event_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  item.isOverdue() ? '$dueLabel · overdue' : dueLabel,
                  style: TextStyle(
                    color: item.isOverdue() ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                  ),
                )),
              ]),
            ]),
          )),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Your progress', style: theme.textTheme.titleMedium)),
                Text('${item.done} / ${item.targetCount}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: item.progressRatio, minHeight: 7),
              const SizedBox(height: 8),
              Text(item.isCompleted ? 'Completed' : '${item.remaining} questions or items remaining'),
              if (item.correct > 0) ...[
                const SizedBox(height: 4),
                Text('${item.correct} correct answers recorded', style: theme.textTheme.bodySmall),
              ],
            ]),
          )),
          const SizedBox(height: 16),
          if (item.isCompleted)
            const _Notice('This assignment is complete. The progress above reflects saved values.')
          else if (item.supportsInAppPractice)
            FilledButton.icon(
              onPressed: _startPractice,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start assignment practice'),
            )
          else
            const _Notice('Instructions are available here. In-app reading/writing response submission is not enabled yet; this task will not be marked submitted from this screen.'),
        ],
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.item, required this.onTap});
  final StudentAssignment item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = item.dueAt;
    final overdue = item.isOverdue();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(item.title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Icon(item.isCompleted ? Icons.check_circle : Icons.chevron_right,
                  color: item.isCompleted ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
            ]),
            const SizedBox(height: 6),
            Text(item.instructions.trim().isEmpty ? 'No extra instructions' : item.instructions,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Chip(visualDensity: VisualDensity.compact, label: Text(_titleCase(item.kind))),
              if (item.skill.isNotEmpty)
                Chip(visualDensity: VisualDensity.compact, label: Text(_titleCase(item.skill))),
              if (overdue)
                const Chip(visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.warning_amber_rounded, size: 17), label: Text('Overdue'))
              else if (due != null)
                Chip(visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.event_outlined, size: 17), label: Text(_dateLabel(due))),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: item.progressRatio, minHeight: 5),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text(item.isCompleted
                  ? 'Completed'
                  : '${item.done} / ${item.targetCount} done', style: theme.textTheme.labelMedium)),
              Text(item.isCompleted ? 'View' : 'Open',
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(children: [
        Text('$count', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.labelMedium),
      ]),
    ));
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ));
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 42),
        const SizedBox(height: 12),
        Text('Could not load assignments', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('Connect to the internet and retry. Assignment access is controlled by your account.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]),
    ));
  }
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  return 'Due ${local.day}/${local.month}/${local.year}';
}

String _titleCase(String value) => value
    .replaceAll('_', ' ')
    .split(RegExp(r'\s+'))
    .map((part) => part.isEmpty
        ? part
        : '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}')
    .join(' ');
