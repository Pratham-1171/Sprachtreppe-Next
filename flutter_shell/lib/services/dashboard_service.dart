import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardData {
  const DashboardData({
    required this.classes,
    required this.pendingAssignments,
    required this.completedAssignments,
    required this.unreadNotifications,
    required this.recentAnnouncements,
  });

  final List<ClassSummary> classes;
  final List<AssignmentSummary> pendingAssignments;
  final int completedAssignments;
  final int unreadNotifications;
  final List<AnnouncementSummary> recentAnnouncements;
}

class ClassSummary {
  const ClassSummary({required this.id, required this.name});
  final int id;
  final String name;
}

class AssignmentSummary {
  const AssignmentSummary({
    required this.id,
    required this.title,
    required this.skill,
    required this.dueAt,
    required this.targetCount,
    required this.done,
    required this.correct,
    required this.className,
  });

  final int id;
  final String title;
  final String skill;
  final DateTime? dueAt;
  final int targetCount;
  final int done;
  final int correct;
  final String className;

  bool get completed => targetCount > 0 ? done >= targetCount : done > 0;
}

class AnnouncementSummary {
  const AnnouncementSummary({
    required this.title,
    required this.body,
    required this.createdAt,
    required this.pinned,
  });

  final String title;
  final String body;
  final DateTime? createdAt;
  final bool pinned;
}

class DashboardService {
  DashboardService(this._client);

  final SupabaseClient _client;

  Future<DashboardData> load(String studentId) async {
    final memberships = await _client
        .from('class_members')
        .select('class_id, classes(id, name)')
        .eq('student_id', studentId);

    final classIds = <int>[];
    final classNames = <int, String>{};
    for (final row in memberships as List) {
      final classId = row['class_id'] as int?;
      if (classId == null) continue;
      classIds.add(classId);
      final nested = row['classes'];
      if (nested is Map) {
        classNames[classId] = (nested['name'] as String?) ?? 'Class';
      }
    }

    var assignments = <AssignmentSummary>[];
    if (classIds.isNotEmpty) {
      final assignmentRows = await _client
          .from('assignments')
          .select('id, class_id, title, skill, due_at, target_count')
          .inFilter('class_id', classIds)
          .eq('archived', false)
          .order('due_at', ascending: true);

      final assignmentIds = <int>[];
      for (final row in assignmentRows as List) {
        assignmentIds.add(row['id'] as int);
      }

      final progressByAssignment = <int, Map<String, dynamic>>{};
      if (assignmentIds.isNotEmpty) {
        final progressRows = await _client
            .from('assignment_progress')
            .select('assignment_id, done, correct')
            .eq('student_id', studentId)
            .inFilter('assignment_id', assignmentIds);
        for (final row in progressRows as List) {
          progressByAssignment[row['assignment_id'] as int] = row;
        }
      }

      assignments = assignmentRows.map<AssignmentSummary>((row) {
        final id = row['id'] as int;
        final progress = progressByAssignment[id];
        return AssignmentSummary(
          id: id,
          title: (row['title'] as String?) ?? 'Assignment',
          skill: (row['skill'] as String?) ?? 'Practice',
          dueAt: DateTime.tryParse(row['due_at'] as String? ?? ''),
          targetCount: (row['target_count'] as int?) ?? 0,
          done: (progress?['done'] as int?) ?? 0,
          correct: (progress?['correct'] as int?) ?? 0,
          className: classNames[row['class_id'] as int] ?? 'Class',
        );
      }).toList();
    }

    final notifications = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', studentId)
        .isFilter('read_at', null);

    final announcementRows = classIds.isEmpty
        ? const <dynamic>[]
        : await _client
            .from('announcements')
            .select('title, body, pinned, created_at')
            .inFilter('class_id', classIds)
            .or('expires_at.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}')
            .order('pinned', ascending: false)
            .order('created_at', ascending: false)
            .limit(5);

    return DashboardData(
      classes: classNames.entries
          .map((entry) => ClassSummary(id: entry.key, name: entry.value))
          .toList(),
      pendingAssignments: assignments.where((a) => !a.completed).take(5).toList(),
      completedAssignments: assignments.where((a) => a.completed).length,
      unreadNotifications: notifications.length,
      recentAnnouncements: (announcementRows as List).map((row) {
        return AnnouncementSummary(
          title: (row['title'] as String?) ?? 'Announcement',
          body: (row['body'] as String?) ?? '',
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
          pinned: (row['pinned'] as bool?) ?? false,
        );
      }).toList(),
    );
  }
}
