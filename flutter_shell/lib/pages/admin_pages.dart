import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_workspace.dart';
import '../services/admin_workspace_service.dart';

enum _AdminSection { dashboard, students, tools }
enum _AdminToolTab { setup, work, review }

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const _AdminDataPage(section: _AdminSection.dashboard);
}

class AdminStudentsPage extends StatelessWidget {
  const AdminStudentsPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const _AdminDataPage(section: _AdminSection.students);
}

class AdminToolsPage extends StatelessWidget {
  const AdminToolsPage({super.key, required this.adminId});
  final String adminId;
  @override
  Widget build(BuildContext context) =>
      _AdminDataPage(section: _AdminSection.tools, adminId: adminId);
}

class _AdminDataPage extends StatefulWidget {
  const _AdminDataPage({required this.section, this.adminId});
  final _AdminSection section;
  final String? adminId;
  @override
  State<_AdminDataPage> createState() => _AdminDataPageState();
}

class _AdminDataPageState extends State<_AdminDataPage> {
  late final AdminWorkspaceService _service;
  late Future<AdminWorkspace> _future;

  @override
  void initState() {
    super.initState();
    _service = AdminWorkspaceService(Supabase.instance.client);
    _reload();
  }

  void _reload() => _future = _service.load();

  Future<void> _refresh() async {
    setState(_reload);
    try {
      await _future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.section) {
      _AdminSection.dashboard => 'Admin dashboard',
      _AdminSection.students => 'Student accounts',
      _AdminSection.tools => 'Admin tools',
    };
    return FutureBuilder<AdminWorkspace>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _AdminError(onRetry: _refresh);
        final data = snapshot.data ??
            const AdminWorkspace(students: [], teachers: [], classes: [], submissions: []);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                widget.section == _AdminSection.dashboard
                    ? 'Account approvals, student activity and review queue.'
                    : widget.section == _AdminSection.students
                        ? 'Approve accounts and view learning progress.'
                        : 'Manage classes, assignments, teacher links and submissions.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              if (widget.section == _AdminSection.dashboard)
                _AdminDashboard(data: data)
              else if (widget.section == _AdminSection.students)
                _AdminStudentList(data: data, service: _service, onChanged: _refresh)
              else
                _AdminTools(
                  data: data,
                  service: _service,
                  adminId: widget.adminId ?? '',
                  onChanged: _refresh,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({required this.data});
  final AdminWorkspace data;

  @override
  Widget build(BuildContext context) {
    final pendingApproval = data.students.where((s) => !s.approved).length;
    final pendingReview = data.submissions.where((s) => s.reviewStatus == 'pending').length;
    final assigned = data.students.fold<int>(0, (n, s) => n + s.assignmentCount);
    final completed = data.students.fold<int>(0, (n, s) => n + s.completedAssignments);
    final metrics = [
      _Metric('Students', data.students.length, Icons.people_outline),
      _Metric('Awaiting approval', pendingApproval, Icons.person_add_alt_1_outlined),
      _Metric('Active classes', data.classes.length, Icons.groups_outlined),
      _Metric('Pending reviews', pendingReview, Icons.rate_review_outlined),
      _Metric('Assignments', assigned, Icons.assignment_outlined),
      _Metric('Completed', completed, Icons.task_alt_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.55,
          ),
          itemBuilder: (context, index) {
            final metric = metrics[index];
            final theme = Theme.of(context);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(metric.icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${metric.count}', style: theme.textTheme.titleLarge),
                          Text(metric.label, maxLines: 2, overflow: TextOverflow.ellipsis),
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
        _SectionHeading(title: 'Awaiting approval', count: pendingApproval),
        const SizedBox(height: 8),
        if (pendingApproval == 0)
          const _EmptyCard('No student accounts are waiting for approval.')
        else
          for (final student in data.students.where((s) => !s.approved).take(5))
            _StudentCard(student: student, onApprove: null),
        const SizedBox(height: 20),
        _SectionHeading(title: 'Recent submissions', count: data.submissions.length),
        const SizedBox(height: 8),
        if (data.submissions.isEmpty)
          const _EmptyCard('No submissions have been recorded yet.')
        else
          for (final submission in data.submissions.take(5))
            _SubmissionCompact(submission: submission),
      ],
    );
  }
}

class _AdminStudentList extends StatefulWidget {
  const _AdminStudentList({
    required this.data,
    required this.service,
    required this.onChanged,
  });
  final AdminWorkspace data;
  final AdminWorkspaceService service;
  final Future<void> Function() onChanged;

  @override
  State<_AdminStudentList> createState() => _AdminStudentListState();
}

class _AdminStudentListState extends State<_AdminStudentList> {
  String _filter = 'All';
  String _query = '';
  final Set<String> _approving = {};

  Future<void> _approve(AdminStudent student) async {
    setState(() => _approving.add(student.id));
    try {
      await widget.service.approveStudent(student.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approved ${student.fullName.isEmpty ? student.email : student.fullName}.')),
      );
      await widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Approval failed. Refresh and try again.')),
      );
    } finally {
      if (mounted) setState(() => _approving.remove(student.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visible = widget.data.students.where((student) {
      final matchesFilter = _filter == 'All' ||
          (_filter == 'Pending' && !student.approved) ||
          (_filter == 'Approved' && student.approved);
      final text = [
        student.fullName,
        student.email,
        ...student.teachers.map((t) => t.name),
        ...student.classes.map((c) => c.name),
      ].join(' ').toLowerCase();
      return matchesFilter && (query.isEmpty || text.contains(query));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            labelText: 'Search students',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'All', label: Text('All')),
            ButtonSegment(value: 'Pending', label: Text('Pending')),
            ButtonSegment(value: 'Approved', label: Text('Approved')),
          ],
          selected: {_filter},
          onSelectionChanged: (value) => setState(() => _filter = value.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 12),
        _SectionHeading(title: 'Student accounts', count: visible.length),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const _EmptyCard('No students match these filters.')
        else
          for (final student in visible)
            _StudentCard(
              student: student,
              approving: _approving.contains(student.id),
              onApprove: student.approved ? null : () => _approve(student),
            ),
      ],
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.onApprove,
    this.approving = false,
  });
  final AdminStudent student;
  final VoidCallback? onApprove;
  final bool approving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = student.assignmentCount == 0
        ? 0.0
        : (student.completedAssignments / student.assignmentCount).clamp(0.0, 1.0).toDouble();
    final activity = student.lastActivity;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Text(student.fullName.trim().isEmpty
                      ? '?'
                      : student.fullName.trim().substring(0, 1).toUpperCase()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(student.fullName.isEmpty ? 'Student' : student.fullName,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(student.email, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(student.approved ? 'Approved' : 'Pending'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: ratio, minHeight: 5),
            const SizedBox(height: 6),
            Text(
              '${student.completedAssignments} of ${student.assignmentCount} assignments completed · '
              '${student.done} items · ${student.correct} correct',
              style: theme.textTheme.bodySmall,
            ),
            if (student.teachers.isNotEmpty || student.classes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final teacher in student.teachers)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.person_outline, size: 16),
                      label: Text(teacher.name),
                    ),
                  for (final classroom in student.classes)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.groups_outlined, size: 16),
                      label: Text(classroom.name),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              activity == null ? 'No recent activity' : 'Last activity ${_dateLabel(activity)}',
              style: theme.textTheme.bodySmall,
            ),
            if (!student.approved && onApprove != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: approving ? null : onApprove,
                  icon: approving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(approving ? 'Approving…' : 'Approve account'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminTools extends StatefulWidget {
  const _AdminTools({
    required this.data,
    required this.service,
    required this.adminId,
    required this.onChanged,
  });
  final AdminWorkspace data;
  final AdminWorkspaceService service;
  final String adminId;
  final Future<void> Function() onChanged;

  @override
  State<_AdminTools> createState() => _AdminToolsState();
}

class _AdminToolsState extends State<_AdminTools> {
  _AdminToolTab _tab = _AdminToolTab.setup;
  final _className = TextEditingController();
  final _teacherEmail = TextEditingController();
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  final _skill = TextEditingController(text: 'grammar');
  final _target = TextEditingController(text: '10');
  String? _teacherId;
  String? _studentId;
  String? _teacherClassId;
  String _assignmentClass = 'all';
  String _kind = 'practice';
  DateTime? _dueAt;
  bool _busy = false;

  @override
  void dispose() {
    _className.dispose();
    _teacherEmail.dispose();
    _title.dispose();
    _instructions.dispose();
    _skill.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action, String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: ${_friendlyError(error)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createClass() async {
    final name = _className.text.trim();
    if (name.isEmpty || name.length > 60) {
      _message('Class name must be 1–60 characters.');
      return;
    }
    await _act(() => widget.service.createClass(name), 'Class created.');
    _className.clear();
  }

  Future<void> _promoteTeacher() async {
    final email = _teacherEmail.text.trim();
    if (!email.contains('@')) {
      _message('Enter the email of an existing account.');
      return;
    }
    await _act(() => widget.service.promoteTeacher(email), 'Teacher role assigned.');
    _teacherEmail.clear();
  }

  Future<void> _assignTeacherClass() async {
    final teacher = _validTeacher(widget.data.teachers, _teacherId);
    final classId = int.tryParse(_teacherClassId ?? '');
    if (teacher == null || classId == null) {
      _message('Choose an approved teacher and a class.');
      return;
    }
    await _act(
      () => widget.service.assignTeacherToClass(classId: classId, teacherId: teacher),
      'Teacher assigned to class.',
    );
  }

  Future<void> _assignStudent() async {
    final teacher = _validTeacher(widget.data.teachers, _teacherId);
    final student = _validStudent(widget.data.students, _studentId);
    if (teacher == null || student == null) {
      _message('Choose an approved student and teacher.');
      return;
    }
    await _act(
      () => widget.service.assignStudentToTeacher(studentId: student, teacherId: teacher),
      'Student assigned to teacher.',
    );
  }

  Future<void> _createAssignment() async {
    final title = _title.text.trim();
    final instructions = _instructions.text.trim();
    final skill = _skill.text.trim();
    final target = int.tryParse(_target.text.trim());
    if (title.isEmpty || title.length > 120) {
      _message('Assignment title must be 1–120 characters.');
      return;
    }
    if (instructions.length > 2000 || skill.length > 30 ||
        target == null || target < 1 || target > 1000) {
      _message('Check instructions, skill and target (1–1000).');
      return;
    }
    final classId = _assignmentClass == 'all' ? null : int.tryParse(_assignmentClass);
    await _act(
      () => widget.service.createAssignment(
        adminId: widget.adminId,
        title: title,
        instructions: instructions,
        kind: _kind,
        skill: skill.isEmpty ? 'any' : skill,
        targetCount: target,
        classId: classId,
        dueAt: _dueAt,
      ),
      'Assignment created.',
    );
    _title.clear();
    _instructions.clear();
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _chooseDueDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (selected != null && mounted) setState(() => _dueAt = selected);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_AdminToolTab>(
            segments: const [
              ButtonSegment(value: _AdminToolTab.setup, label: Text('Setup')),
              ButtonSegment(value: _AdminToolTab.work, label: Text('Work')),
              ButtonSegment(value: _AdminToolTab.review, label: Text('Review')),
            ],
            selected: {_tab},
            onSelectionChanged: (value) => setState(() => _tab = value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 14),
          if (_tab == _AdminToolTab.setup)
            _setup(context)
          else if (_tab == _AdminToolTab.work)
            _work(context)
          else
            _review(context),
        ],
      );

  Widget _setup(BuildContext context) {
    final teachers = widget.data.teachers;
    final students = widget.data.students.where((student) => student.approved).toList();
    final teacherId = _validTeacher(teachers, _teacherId);
    final studentId = _validStudent(students, _studentId);
    final classId = _validClass(widget.data.classes, _teacherClassId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormCard(
          title: 'Create a class',
          note: 'Class names can contain up to 60 characters.',
          children: [
            TextField(controller: _className, maxLength: 60,
                decoration: const InputDecoration(labelText: 'Class name')),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _createClass,
              child: const Text('Create class'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _FormCard(
          title: 'Assign an existing account as teacher',
          note: 'This uses the admin-only role assignment RPC and does not create a login.',
          children: [
            TextField(controller: _teacherEmail, keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Existing account email')),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _promoteTeacher,
              child: const Text('Assign teacher role'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _FormCard(
          title: 'Assign teacher to class',
          note: teachers.isEmpty || widget.data.classes.isEmpty
              ? 'Add at least one approved teacher and one class first.'
              : 'Only approved teachers and active classes are listed.',
          children: [
            if (teachers.isNotEmpty && widget.data.classes.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: teacherId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Teacher'),
                items: [
                  for (final teacher in teachers)
                    DropdownMenuItem(value: teacher.id, child: Text(teacher.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _busy ? null : (value) => setState(() => _teacherId = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: classId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Class'),
                items: [
                  for (final classroom in widget.data.classes)
                    DropdownMenuItem(value: classroom.id.toString(), child: Text(classroom.name)),
                ],
                onChanged: _busy ? null : (value) => setState(() => _teacherClassId = value),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _assignTeacherClass,
                child: const Text('Assign teacher'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _FormCard(
          title: 'Assign student to teacher',
          note: teachers.isEmpty || students.isEmpty
              ? 'You need an approved student and teacher first.'
              : 'Creates the teacher–student link used by the teacher dashboard.',
          children: [
            if (teachers.isNotEmpty && students.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: studentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Student'),
                items: [
                  for (final student in students)
                    DropdownMenuItem(
                      value: student.id,
                      child: Text(student.fullName.isEmpty ? student.email : student.fullName,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _busy ? null : (value) => setState(() => _studentId = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: teacherId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Teacher'),
                items: [
                  for (final teacher in teachers)
                    DropdownMenuItem(value: teacher.id, child: Text(teacher.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _busy ? null : (value) => setState(() => _teacherId = value),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _assignStudent,
                child: const Text('Assign student'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _work(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FormCard(
            title: 'Create assignment',
            note: 'Valid task types are practice, reading and writing. Targets are limited to 1–1000.',
            children: [
              TextField(controller: _title, maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 8),
              TextField(
                controller: _instructions,
                maxLength: 2000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Instructions', alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Task type'),
                items: const [
                  DropdownMenuItem(value: 'practice', child: Text('Practice')),
                  DropdownMenuItem(value: 'reading', child: Text('Reading response')),
                  DropdownMenuItem(value: 'writing', child: Text('Writing response')),
                ],
                onChanged: _busy ? null : (value) => setState(() => _kind = value ?? 'practice'),
              ),
              const SizedBox(height: 8),
              TextField(controller: _skill, maxLength: 30,
                  decoration: const InputDecoration(labelText: 'Skill (e.g. grammar, vocabulary)')),
              const SizedBox(height: 8),
              TextField(controller: _target, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Target count')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _validAssignmentClass(_assignmentClass, widget.data.classes),
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Assign to'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All students')),
                  for (final classroom in widget.data.classes)
                    DropdownMenuItem(value: classroom.id.toString(), child: Text(classroom.name)),
                ],
                onChanged: _busy ? null : (value) => setState(() => _assignmentClass = value ?? 'all'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseDueDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(_dueAt == null ? 'Optional deadline' : 'Due ${_dateLabel(_dueAt)}'),
              ),
              if (_dueAt != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: _busy ? null : () => setState(() => _dueAt = null),
                      child: const Text('Remove deadline')),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _createAssignment,
                  icon: const Icon(Icons.assignment_turned_in_outlined),
                  label: const Text('Create assignment'),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _review(BuildContext context) {
    final pending = widget.data.submissions.where((s) => s.reviewStatus == 'pending').toList();
    final done = widget.data.submissions.where((s) => s.reviewStatus != 'pending').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(title: 'Pending review', count: pending.length),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const _EmptyCard('No pending submissions in the latest 100 records.')
        else
          for (final submission in pending)
            _SubmissionReviewCard(
              key: ValueKey<int>(submission.id),
              submission: submission,
              service: widget.service,
              adminId: widget.adminId,
              onSaved: widget.onChanged,
            ),
        const SizedBox(height: 18),
        _SectionHeading(title: 'Recently reviewed / flagged', count: done.length),
        const SizedBox(height: 8),
        for (final submission in done.take(8))
          _SubmissionCompact(submission: submission),
        const SizedBox(height: 10),
        const _InlineNote('Review notes are sent as unread feedback on the student’s next sync.'),
      ],
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _SubmissionReviewCard extends StatefulWidget {
  const _SubmissionReviewCard({
    super.key,
    required this.submission,
    required this.service,
    required this.adminId,
    required this.onSaved,
  });
  final AdminSubmission submission;
  final AdminWorkspaceService service;
  final String adminId;
  final Future<void> Function() onSaved;

  @override
  State<_SubmissionReviewCard> createState() => _SubmissionReviewCardState();
}

class _SubmissionReviewCardState extends State<_SubmissionReviewCard> {
  late final TextEditingController _note;
  int _rating = 5;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.submission.reviewNote ?? '');
    _rating = widget.submission.rating ?? 5;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(String status) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.service.reviewSubmission(
        submissionId: widget.submission.id,
        adminId: widget.adminId,
        status: status,
        note: _note.text,
        rating: _rating,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status == 'reviewed' ? 'Feedback saved.' : 'Submission flagged.')),
      );
      await widget.onSaved();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review update failed. Refresh and try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;
    final response = submission.writtenResponse;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(submission.assignmentTitle),
        subtitle: Text(
          '${submission.studentName} · ${submission.studentEmail}\n${_dateLabel(submission.createdAt)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              response ?? 'This record contains learning progress metadata rather than a written response.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Feedback note for student',
              alignLabelWithHint: true,
            ),
          ),
          Row(
            children: [
              const Expanded(child: Text('Rating')),
              DropdownButton<int>(
                value: _rating,
                items: [
                  for (var value = 1; value <= 5; value++)
                    DropdownMenuItem(value: value, child: Text('$value / 5')),
                ],
                onChanged: _saving ? null : (value) => setState(() => _rating = value ?? 5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save('flagged'),
                  child: const Text('Flag'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save('reviewed'),
                  child: Text(_saving ? 'Saving…' : 'Save review'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubmissionCompact extends StatelessWidget {
  const _SubmissionCompact({required this.submission});
  final AdminSubmission submission;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(submission.reviewStatus == 'flagged' ? Icons.flag_outlined : Icons.rate_review_outlined),
          title: Text(submission.assignmentTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${submission.studentName} · ${_dateLabel(submission.createdAt)}\nStatus: ${_label(submission.reviewStatus)}',
          ),
          isThreeLine: true,
        ),
      );
}

class _Metric {
  const _Metric(this.label, this.count, this.icon);
  final String label;
  final int count;
  final IconData icon;
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

class _FormCard extends StatelessWidget {
  const _FormCard({required this.title, required this.note, required this.children});
  final String title;
  final String note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(note, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );
}

class _InlineNote extends StatelessWidget {
  const _InlineNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      );
}

class _AdminError extends StatelessWidget {
  const _AdminError({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 42),
              const SizedBox(height: 12),
              Text('Could not load admin workspace',
                  style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              const Text('Check this account’s administrator role, then retry.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      );
}

String? _validTeacher(List<AdminTeacher> teachers, String? id) {
  if (id != null && teachers.any((t) => t.id == id)) return id;
  return teachers.isEmpty ? null : teachers.first.id;
}

String? _validStudent(List<AdminStudent> students, String? id) {
  if (id != null && students.any((s) => s.id == id && s.approved)) return id;
  for (final student in students) {
    if (student.approved) return student.id;
  }
  return null;
}

String? _validClass(List<AdminClassInfo> classes, String? id) {
  if (id != null && classes.any((c) => c.id.toString() == id)) return id;
  return classes.isEmpty ? null : classes.first.id.toString();
}

String _validAssignmentClass(String value, List<AdminClassInfo> classes) {
  if (value == 'all' || classes.any((c) => c.id.toString() == value)) return value;
  return 'all';
}

String _dateLabel(DateTime? value) {
  if (value == null) return 'Date unavailable';
  final date = value.toLocal();
  return '${date.day}/${date.month}/${date.year}';
}

String _label(String value) {
  if (value.trim().isEmpty) return 'Other';
  return value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .map((part) => part.isEmpty ? part : '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}
