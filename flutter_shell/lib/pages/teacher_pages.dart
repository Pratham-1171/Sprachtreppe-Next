import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/teacher_workspace.dart';
import '../services/teacher_workspace_service.dart';

enum _TeacherSection { dashboard, classes, work }

class TeacherDashboardPage extends StatelessWidget {
  const TeacherDashboardPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _TeacherWorkspacePage(section: _TeacherSection.dashboard);
}

class TeacherClassesPage extends StatelessWidget {
  const TeacherClassesPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _TeacherWorkspacePage(section: _TeacherSection.classes);
}

class TeacherWorkPage extends StatelessWidget {
  const TeacherWorkPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _TeacherWorkspacePage(section: _TeacherSection.work);
}

class _TeacherWorkspacePage extends StatefulWidget {
  const _TeacherWorkspacePage({required this.section});

  final _TeacherSection section;

  @override
  State<_TeacherWorkspacePage> createState() => _TeacherWorkspacePageState();
}

class _TeacherWorkspacePageState extends State<_TeacherWorkspacePage> {
  late final TeacherWorkspaceService _service;
  late Future<TeacherWorkspace> _future;
  bool _publishingAnnouncement = false;
  bool _creatingAssignment = false;

  @override
  void initState() {
    super.initState();
    _service = TeacherWorkspaceService(Supabase.instance.client);
    _load();
  }

  void _load() {
    _future = _service.load();
  }

  Future<void> _refresh() async {
    setState(_load);
    try {
      await _future;
    } catch (_) {
      // FutureBuilder shows a retryable error state.
    }
  }

  Future<void> _createAssignment(TeacherWorkspace data) async {
    if (_creatingAssignment || data.classes.isEmpty) return;
    final draft = await showDialog<_TeacherAssignmentDraft>(
      context: context,
      builder: (_) => _TeacherAssignmentDialog(classes: data.classes),
    );
    if (draft == null || !mounted) return;

    setState(() => _creatingAssignment = true);
    try {
      await _service.createAssignment(
        classId: draft.classId,
        title: draft.title,
        instructions: draft.instructions,
        skill: draft.skill,
        targetCount: draft.targetCount,
        dueAt: draft.dueAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assignment created and students notified.')),
      );
      setState(_load);
      try {
        await _future;
      } catch (_) {
        // The server confirmed creation. FutureBuilder shows any refresh error.
      }
    } catch (error) {
      if (!mounted) return;
      var message = error.toString().replaceFirst('Exception: ', '').replaceFirst('Invalid argument(s): ', '');
      if (message.length > 180) message = '${message.substring(0, 177)}…';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create assignment: $message')),
      );
    } finally {
      if (mounted) setState(() => _creatingAssignment = false);
    }
  }

  Future<void> _createAnnouncement(TeacherWorkspace data) async {
    if (_publishingAnnouncement || data.classes.isEmpty) return;
    final draft = await showDialog<_TeacherAnnouncementDraft>(
      context: context,
      builder: (_) => _TeacherAnnouncementDialog(classes: data.classes),
    );
    if (draft == null || !mounted) return;

    setState(() => _publishingAnnouncement = true);
    try {
      await _service.createAnnouncement(
        classId: draft.classId,
        title: draft.title,
        body: draft.body,
        pinned: draft.pinned,
        expiresAt: draft.expiresAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement published to the selected class.')),
      );
      setState(_load);
      try {
        await _future;
      } catch (_) {
        // The server confirmed publication. FutureBuilder shows refresh errors.
      }
    } catch (error) {
      if (!mounted) return;
      var message = error.toString().replaceFirst('Exception: ', '').replaceFirst('Invalid argument(s): ', '');
      if (message.length > 180) message = '${message.substring(0, 177)}…';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not publish announcement: $message')),
      );
    } finally {
      if (mounted) setState(() => _publishingAnnouncement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.section) {
      _TeacherSection.dashboard => 'Teacher dashboard',
      _TeacherSection.classes => 'My classes',
      _TeacherSection.work => 'Class work',
    };
    return FutureBuilder<TeacherWorkspace>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _TeacherError(onRetry: _refresh);
        }
        final data = snapshot.data ??
            const TeacherWorkspace(
              classes: [],
              assignments: [],
              announcements: [],
              students: [],
            );
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                switch (widget.section) {
                  _TeacherSection.dashboard =>
                    'A quick view of your assigned students and learning activity.',
                  _TeacherSection.classes =>
                    'Classes assigned to your teacher account, with related work and announcements.',
                  _TeacherSection.work =>
                    'Assignments created for your classes or by your teacher account.',
                },
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              if (widget.section == _TeacherSection.work) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _creatingAssignment || data.classes.isEmpty
                        ? null
                        : () => _createAssignment(data),
                    icon: _creatingAssignment
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_task),
                    label: Text(_creatingAssignment ? 'Creating…' : 'Create class assignment'),
                  ),
                ),
                const SizedBox(height: 12),
                if (data.classes.isEmpty)
                  const Text('You need an assigned class before you can create class work.'),
              ],
              if (widget.section == _TeacherSection.classes) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _publishingAnnouncement || data.classes.isEmpty
                        ? null
                        : () => _createAnnouncement(data),
                    icon: _publishingAnnouncement
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.campaign_outlined),
                    label: Text(_publishingAnnouncement ? 'Publishing…' : 'New announcement'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              switch (widget.section) {
                _TeacherSection.dashboard => _DashboardContent(data: data),
                _TeacherSection.classes => _ClassesContent(data: data),
                _TeacherSection.work => _WorkContent(data: data),
              },
              const SizedBox(height: 12),
              Text(
                'Data is loaded from teacher-scoped Supabase functions. Pull down to refresh.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.data});

  final TeacherWorkspace data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final students = data.students;
    final assigned = students.fold<int>(0, (sum, s) => sum + s.assignmentCount);
    final completed =
        students.fold<int>(0, (sum, s) => sum + s.completedAssignments);
    final totals = [
      ('Classes', data.classes.length, Icons.groups_outlined),
      ('Students', students.length, Icons.school_outlined),
      ('Assignments', assigned, Icons.assignment_outlined),
      ('Completed', completed, Icons.task_alt_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totals.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.65,
          ),
          itemBuilder: (context, index) {
            final item = totals[index];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(item.$3, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${item.$2}', style: theme.textTheme.titleLarge),
                          Text(item.$1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        _SectionHeading(title: 'Assigned students', count: students.length),
        const SizedBox(height: 8),
        if (students.isEmpty)
          const _EmptyCard(
            icon: Icons.person_search_outlined,
            message: 'No students are assigned to your teacher account yet.',
          )
        else
          for (final student in students)
            _StudentCard(student: student),
        const SizedBox(height: 20),
        _SectionHeading(title: 'Recent class work', count: data.assignments.length),
        const SizedBox(height: 8),
        if (data.assignments.isEmpty)
          const _EmptyCard(
            icon: Icons.assignment_outlined,
            message: 'No active assignments are available for your classes.',
          )
        else
          for (final assignment in data.assignments.take(4))
            _AssignmentCard(
              assignment: assignment,
              className: _classNameFor(data.classes, assignment.classId),
            ),
      ],
    );
  }
}

class _ClassesContent extends StatelessWidget {
  const _ClassesContent({required this.data});

  final TeacherWorkspace data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.classes.isEmpty) {
      return const _EmptyCard(
        icon: Icons.groups_outlined,
        message: 'No classes are assigned to your teacher account yet.',
      );
    }
    return Column(
      children: [
        for (final classroom in data.classes)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
              title: Text(
                classroom.name,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${data.assignments.where((a) => a.classId == classroom.id).length} active assignments · '
                '${data.announcements.where((a) => a.classId == classroom.id).length} announcements',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                _SectionHeading(
                  title: 'Assignments',
                  count: data.assignments.where((a) => a.classId == classroom.id).length,
                ),
                const SizedBox(height: 8),
                for (final assignment
                    in data.assignments.where((a) => a.classId == classroom.id))
                  _AssignmentCard(assignment: assignment, className: classroom.name),
                if (!data.assignments.any((a) => a.classId == classroom.id))
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No active assignments for this class.'),
                  ),
                const SizedBox(height: 12),
                _SectionHeading(
                  title: 'Announcements',
                  count: data.announcements.where((a) => a.classId == classroom.id).length,
                ),
                const SizedBox(height: 8),
                for (final announcement
                    in data.announcements.where((a) => a.classId == classroom.id))
                  _AnnouncementCard(announcement: announcement),
                if (!data.announcements.any((a) => a.classId == classroom.id))
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No announcements for this class.'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WorkContent extends StatelessWidget {
  const _WorkContent({required this.data});

  final TeacherWorkspace data;

  @override
  Widget build(BuildContext context) {
    if (data.assignments.isEmpty) {
      return const _EmptyCard(
        icon: Icons.assignment_outlined,
        message: 'No active work has been assigned to your teacher account.',
      );
    }
    return Column(
      children: [
        for (final assignment in data.assignments)
          _AssignmentCard(
            assignment: assignment,
            className: _classNameFor(data.classes, assignment.classId),
          ),
        const SizedBox(height: 8),
        const _InfoNotice(
          message: 'Create practice assignments for your assigned classes above. Creation is validated by a server-side role and class-membership check; editing and archiving remain admin-controlled.',
        ),
      ],
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student});

  final TeacherStudent student;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastActivity = student.lastActivity;
    final activityLabel = lastActivity == null
        ? 'No recorded activity'
        : 'Last activity ${_dateLabel(lastActivity)}';
    final assignmentRatio = student.assignmentCount == 0
        ? 0.0
        : (student.completedAssignments / student.assignmentCount)
            .clamp(0.0, 1.0)
            .toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    student.fullName.trim().isEmpty
                        ? '?'
                        : student.fullName.trim().substring(0, 1).toUpperCase(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.fullName.isEmpty ? 'Student' : student.fullName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(student.email, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (!student.approved)
                  const Chip(
                    label: Text('Pending'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: assignmentRatio, minHeight: 5),
            const SizedBox(height: 6),
            Text(
              '${student.completedAssignments} of ${student.assignmentCount} assignments completed',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 3),
            Text(activityLabel, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.assignment, required this.className});

  final TeacherAssignment assignment;
  final String? className;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueAt = assignment.dueAt;
    final dueText = dueAt == null ? 'No deadline' : 'Due ${_dateLabel(dueAt)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              assignment.title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (assignment.instructions.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(assignment.instructions, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_label(assignment.kind)),
                ),
                if (assignment.skill.isNotEmpty)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_label(assignment.skill)),
                  ),
                if (className?.isNotEmpty == true)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.groups_outlined, size: 17),
                    label: Text(className!),
                  ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.flag_outlined, size: 17),
                  label: Text('Target ${assignment.targetCount}'),
                ),
              ],
            ),
            Text(dueText, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});

  final TeacherAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          announcement.pinned ? Icons.push_pin : Icons.campaign_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(announcement.title),
        subtitle: Text(announcement.body, maxLines: 3, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text('$count'),
        ],
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 38),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _InfoNotice extends StatelessWidget {
  const _InfoNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
}

class _TeacherError extends StatelessWidget {
  const _TeacherError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 42),
              const SizedBox(height: 12),
              Text(
                'Could not load teacher workspace',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Make sure your administrator has assigned you to the correct teacher role, then retry.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}

String? _classNameFor(List<TeacherClass> classes, int? id) {
  if (id == null) return 'Created by teacher';
  for (final classroom in classes) {
    if (classroom.id == id) return classroom.name;
  }
  return null;
}

String _dateLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.day}/${local.month}/${local.year}';
}

String _label(String value) {
  if (value.trim().isEmpty) return 'Other';
  return value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .map((part) => part.isEmpty
          ? part
          : '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}


class _TeacherAnnouncementDraft {
  const _TeacherAnnouncementDraft({
    required this.classId,
    required this.title,
    required this.body,
    required this.pinned,
    required this.expiresAt,
  });

  final int classId;
  final String title;
  final String body;
  final bool pinned;
  final DateTime? expiresAt;
}

class _TeacherAnnouncementDialog extends StatefulWidget {
  const _TeacherAnnouncementDialog({required this.classes});

  final List<TeacherClass> classes;

  @override
  State<_TeacherAnnouncementDialog> createState() => _TeacherAnnouncementDialogState();
}

class _TeacherAnnouncementDialogState extends State<_TeacherAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  int? _classId;
  bool _pinned = false;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    if (widget.classes.isNotEmpty) _classId = widget.classes.first.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _chooseExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (date != null && mounted) setState(() => _expiresAt = date);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Publish announcement'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _classId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Class'),
                    items: [
                      for (final classroom in widget.classes)
                        DropdownMenuItem<int>(
                          value: classroom.id,
                          child: Text(classroom.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    validator: (value) => value == null ? 'Choose a class' : null,
                    onChanged: (value) => setState(() => _classId = value),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _title,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (value) =>
                        (value?.trim().isEmpty ?? true) ? 'Enter an announcement title' : null,
                  ),
                  TextFormField(
                    controller: _body,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      hintText: 'Exam reminders, revision plans or class updates…',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) =>
                        (value?.trim().isEmpty ?? true) ? 'Enter a message' : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pin announcement'),
                    subtitle: const Text('Pinned messages appear first.'),
                    value: _pinned,
                    onChanged: (value) => setState(() => _pinned = value),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _chooseExpiry,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_expiresAt == null ? 'Optional expiry date' : 'Expires ${_dateLabel(_expiresAt!)}'),
                    ),
                  ),
                  if (_expiresAt != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _expiresAt = null),
                        child: const Text('Keep announcement until removed'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate() || _classId == null) return;
              Navigator.pop(
                context,
                _TeacherAnnouncementDraft(
                  classId: _classId!,
                  title: _title.text.trim(),
                  body: _body.text.trim(),
                  pinned: _pinned,
                  expiresAt: _expiresAt,
                ),
              );
            },
            child: const Text('Publish'),
          ),
        ],
      );
}


class _TeacherAssignmentDraft {
  const _TeacherAssignmentDraft({
    required this.classId,
    required this.title,
    required this.instructions,
    required this.skill,
    required this.targetCount,
    required this.dueAt,
  });

  final int classId;
  final String title;
  final String instructions;
  final String skill;
  final int targetCount;
  final DateTime? dueAt;
}

class _TeacherAssignmentDialog extends StatefulWidget {
  const _TeacherAssignmentDialog({required this.classes});

  final List<TeacherClass> classes;

  @override
  State<_TeacherAssignmentDialog> createState() => _TeacherAssignmentDialogState();
}

class _TeacherAssignmentDialogState extends State<_TeacherAssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  final _skill = TextEditingController(text: 'grammar');
  final _target = TextEditingController(text: '20');
  int? _classId;
  DateTime? _dueAt;

  @override
  void initState() {
    super.initState();
    if (widget.classes.isNotEmpty) _classId = widget.classes.first.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    _skill.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _chooseDueDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (selected != null && mounted) setState(() => _dueAt = selected);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create class assignment'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _classId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Class'),
                    items: [
                      for (final classroom in widget.classes)
                        DropdownMenuItem<int>(
                          value: classroom.id,
                          child: Text(classroom.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    validator: (value) => value == null ? 'Choose a class' : null,
                    onChanged: (value) => setState(() => _classId = value),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _title,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (value) =>
                        (value?.trim().isEmpty ?? true) ? 'Enter an assignment title' : null,
                  ),
                  TextFormField(
                    controller: _instructions,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Instructions',
                      alignLabelWithHint: true,
                    ),
                  ),
                  TextFormField(
                    controller: _skill,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'Skill',
                      hintText: 'grammar, vocabulary or reading',
                    ),
                  ),
                  TextFormField(
                    controller: _target,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Target questions/items'),
                    validator: (value) {
                      final target = int.tryParse(value ?? '');
                      return target == null || target < 1 || target > 1000
                          ? 'Enter a number from 1 to 1000'
                          : null;
                    },
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _chooseDueDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_dueAt == null ? 'Optional deadline' : 'Due ${_dateLabel(_dueAt!)}'),
                    ),
                  ),
                  if (_dueAt != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _dueAt = null),
                        child: const Text('Remove deadline'),
                      ),
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    'The server validates that you are assigned to the selected class.',
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate() || _classId == null) return;
              Navigator.pop(
                context,
                _TeacherAssignmentDraft(
                  classId: _classId!,
                  title: _title.text.trim(),
                  instructions: _instructions.text.trim(),
                  skill: _skill.text.trim(),
                  targetCount: int.parse(_target.text),
                  dueAt: _dueAt,
                ),
              );
            },
            child: const Text('Create assignment'),
          ),
        ],
      );
}
