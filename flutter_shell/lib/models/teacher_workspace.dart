class TeacherWorkspace {
  const TeacherWorkspace({
    required this.classes,
    required this.assignments,
    required this.announcements,
    required this.students,
  });

  final List<TeacherClass> classes;
  final List<TeacherAssignment> assignments;
  final List<TeacherAnnouncement> announcements;
  final List<TeacherStudent> students;

  factory TeacherWorkspace.fromRpc({
    required dynamic classroom,
    required dynamic students,
  }) {
    final classroomMap = _jsonMap(classroom) ?? const <String, dynamic>{};
    return TeacherWorkspace(
      classes: _jsonRows(classroomMap['classes'])
          .map(TeacherClass.fromJson)
          .toList(),
      assignments: _jsonRows(classroomMap['assignments'])
          .map(TeacherAssignment.fromJson)
          .toList(),
      announcements: _jsonRows(classroomMap['announcements'])
          .map(TeacherAnnouncement.fromJson)
          .toList(),
      students: _jsonRows(students).map(TeacherStudent.fromJson).toList(),
    );
  }

  static Map<String, dynamic>? _jsonMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<Map<String, dynamic>> _jsonRows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class TeacherClass {
  const TeacherClass({
    required this.id,
    required this.name,
    required this.archived,
  });

  final int id;
  final String name;
  final bool archived;

  factory TeacherClass.fromJson(Map<String, dynamic> json) => TeacherClass(
        id: _teacherInt(json['id']),
        name: json['name'] as String? ?? 'Class',
        archived: json['archived'] as bool? ?? false,
      );
}

class TeacherAssignment {
  const TeacherAssignment({
    required this.id,
    required this.classId,
    required this.title,
    required this.instructions,
    required this.kind,
    required this.skill,
    required this.targetCount,
    required this.dueAt,
    required this.createdAt,
    required this.createdBy,
  });

  final int id;
  final int? classId;
  final String title;
  final String instructions;
  final String kind;
  final String skill;
  final int targetCount;
  final DateTime? dueAt;
  final DateTime? createdAt;
  final String? createdBy;

  factory TeacherAssignment.fromJson(Map<String, dynamic> json) {
    final rawClassId = json['class_id'];
    return TeacherAssignment(
      id: _teacherInt(json['id']),
      classId: rawClassId == null ? null : _teacherInt(rawClassId),
      title: json['title'] as String? ?? 'Assignment',
      instructions: json['instructions'] as String? ?? '',
      kind: json['kind'] as String? ?? 'practice',
      skill: json['skill'] as String? ?? 'any',
      targetCount: _teacherInt(json['target_count'], fallback: 1),
      dueAt: DateTime.tryParse(json['due_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      createdBy: json['created_by']?.toString(),
    );
  }
}

class TeacherAnnouncement {
  const TeacherAnnouncement({
    required this.id,
    required this.classId,
    required this.title,
    required this.body,
    required this.pinned,
    required this.expiresAt,
    required this.createdAt,
  });

  final int id;
  final int? classId;
  final String title;
  final String body;
  final bool pinned;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory TeacherAnnouncement.fromJson(Map<String, dynamic> json) {
    final rawClassId = json['class_id'];
    return TeacherAnnouncement(
      id: _teacherInt(json['id']),
      classId: rawClassId == null ? null : _teacherInt(rawClassId),
      title: json['title'] as String? ?? 'Announcement',
      body: json['body'] as String? ?? '',
      pinned: json['pinned'] as bool? ?? false,
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class TeacherStudent {
  const TeacherStudent({
    required this.id,
    required this.fullName,
    required this.email,
    required this.approved,
    required this.assignmentCount,
    required this.completedAssignments,
    required this.done,
    required this.correct,
    required this.lastActivity,
  });

  final String id;
  final String fullName;
  final String email;
  final bool approved;
  final int assignmentCount;
  final int completedAssignments;
  final int done;
  final int correct;
  final DateTime? lastActivity;

  factory TeacherStudent.fromJson(Map<String, dynamic> json) => TeacherStudent(
        id: json['id']?.toString() ?? '',
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        approved: json['approved'] as bool? ?? false,
        assignmentCount: _teacherInt(json['assignment_count']),
        completedAssignments: _teacherInt(json['completed_assignments']),
        done: _teacherInt(json['done']),
        correct: _teacherInt(json['correct']),
        lastActivity: DateTime.tryParse(json['last_activity']?.toString() ?? ''),
      );
}

int _teacherInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
