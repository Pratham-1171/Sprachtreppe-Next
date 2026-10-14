class AdminWorkspace {
  const AdminWorkspace({
    required this.students,
    required this.teachers,
    required this.classes,
    required this.submissions,
  });

  final List<AdminStudent> students;
  final List<AdminTeacher> teachers;
  final List<AdminClassInfo> classes;
  final List<AdminSubmission> submissions;

  factory AdminWorkspace.fromRows({
    required dynamic students,
    required dynamic teachers,
    required dynamic classes,
    required dynamic submissions,
    required Map<String, Map<String, dynamic>> profilesById,
  }) {
    return AdminWorkspace(
      students: _adminRows(students).map(AdminStudent.fromJson).toList(),
      teachers: _adminRows(teachers).map(AdminTeacher.fromJson).toList(),
      classes: _adminRows(classes).map(AdminClassInfo.fromJson).toList(),
      submissions: _adminRows(submissions).map((row) {
        final profile = profilesById[row['student_id']?.toString() ?? ''];
        return AdminSubmission.fromJson(row, profile: profile);
      }).toList(),
    );
  }
}

class AdminStudent {
  const AdminStudent({
    required this.id,
    required this.fullName,
    required this.email,
    required this.approved,
    required this.teachers,
    required this.classes,
    required this.assignmentCount,
    required this.completedAssignments,
    required this.done,
    required this.correct,
    required this.lastActivity,
    required this.pendingSubmissions,
  });

  final String id;
  final String fullName;
  final String email;
  final bool approved;
  final List<AdminLabelRef> teachers;
  final List<AdminLabelRef> classes;
  final int assignmentCount;
  final int completedAssignments;
  final int done;
  final int correct;
  final DateTime? lastActivity;
  final int pendingSubmissions;

  factory AdminStudent.fromJson(Map<String, dynamic> json) => AdminStudent(
        id: json['id']?.toString() ?? '',
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        approved: json['approved'] as bool? ?? false,
        teachers: _adminRows(json['teachers']).map(AdminLabelRef.fromJson).toList(),
        classes: _adminRows(json['classes']).map(AdminLabelRef.fromJson).toList(),
        assignmentCount: _adminInt(json['assignment_count']),
        completedAssignments: _adminInt(json['completed_assignments']),
        done: _adminInt(json['done']),
        correct: _adminInt(json['correct']),
        lastActivity: DateTime.tryParse(json['last_activity']?.toString() ?? ''),
        pendingSubmissions: _adminInt(json['pending_submissions']),
      );
}

class AdminLabelRef {
  const AdminLabelRef({required this.id, required this.name});

  final String id;
  final String name;

  factory AdminLabelRef.fromJson(Map<String, dynamic> json) => AdminLabelRef(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
      );
}

class AdminTeacher {
  const AdminTeacher({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  factory AdminTeacher.fromJson(Map<String, dynamic> json) => AdminTeacher(
        id: json['id']?.toString() ?? '',
        name: (json['full_name'] as String?)?.trim().isNotEmpty == true
            ? (json['full_name'] as String).trim()
            : (json['email'] as String? ?? 'Teacher'),
        email: json['email'] as String? ?? '',
      );
}

class AdminClassInfo {
  const AdminClassInfo({required this.id, required this.name});

  final int id;
  final String name;

  factory AdminClassInfo.fromJson(Map<String, dynamic> json) => AdminClassInfo(
        id: _adminInt(json['id']),
        name: json['name'] as String? ?? 'Class',
      );
}

class AdminSubmission {
  const AdminSubmission({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    required this.createdAt,
    required this.summary,
    required this.payload,
    required this.reviewStatus,
    required this.reviewNote,
    required this.rating,
    required this.reviewedAt,
  });

  final int id;
  final String studentId;
  final String studentName;
  final String studentEmail;
  final DateTime? createdAt;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> payload;
  final String reviewStatus;
  final String? reviewNote;
  final int? rating;
  final DateTime? reviewedAt;

  String get assignmentTitle {
    final response = _adminMap(payload['assignment_response']);
    return (response?['title'] as String?) ??
        (summary['assignment_title'] as String?) ??
        'Learning activity';
  }

  String? get writtenResponse {
    final response = _adminMap(payload['assignment_response']);
    final value = response?['text'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  factory AdminSubmission.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? profile,
  }) {
    final summary = _adminMap(json['summary']) ?? const <String, dynamic>{};
    final payload = _adminMap(json['payload']) ?? const <String, dynamic>{};
    return AdminSubmission(
      id: _adminInt(json['id']),
      studentId: json['student_id']?.toString() ?? '',
      studentName: profile?['full_name'] as String? ?? 'Student',
      studentEmail: profile?['email'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      summary: summary,
      payload: payload,
      reviewStatus: json['review_status'] as String? ?? 'pending',
      reviewNote: json['review_note'] as String?,
      rating: json['rating'] is num ? (json['rating'] as num).toInt() : null,
      reviewedAt: DateTime.tryParse(json['reviewed_at']?.toString() ?? ''),
    );
  }
}

Map<String, dynamic>? _adminMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>> _adminRows(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

int _adminInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
