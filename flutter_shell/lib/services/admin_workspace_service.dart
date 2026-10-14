import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_workspace.dart';

class AdminWorkspaceService {
  AdminWorkspaceService(this._client);

  final SupabaseClient _client;

  Future<AdminWorkspace> load() async {
    // The overview RPC is admin-only; direct profile and submission reads are
    // still protected by their respective RLS policies.
    final result = await Future.wait<dynamic>([
      _client.rpc('admin_students_overview'),
      _client
          .from('profiles')
          .select('id, full_name, email, role, approved')
          .eq('role', 'teacher')
          .eq('approved', true)
          .order('full_name'),
      _client
          .from('classes')
          .select('id, name, archived')
          .eq('archived', false)
          .order('name'),
      _client
          .from('submissions')
          .select(
            'id, student_id, client_id, created_at, summary, payload, '
            'review_status, review_note, rating, reviewed_at, student_seen',
          )
          .order('created_at', ascending: false)
          .limit(100),
    ]);

    final students = _adminRows(result[0]);
    final teachers = _adminRows(result[1]);
    final classes = _adminRows(result[2]);
    final submissions = _adminRows(result[3]);
    final ids = <String>{
      for (final row in students)
        if (row['id'] != null) row['id'].toString(),
      for (final row in submissions)
        if (row['student_id'] != null) row['student_id'].toString(),
    };

    final profilesById = <String, Map<String, dynamic>>{};
    if (ids.isNotEmpty) {
      final rawProfiles = await _client
          .from('profiles')
          .select('id, full_name, email')
          .inFilter('id', ids.toList());
      for (final row in rawProfiles as List) {
        if (row is! Map) continue;
        final profile = Map<String, dynamic>.from(row);
        profilesById[profile['id']?.toString() ?? ''] = profile;
      }
    }

    return AdminWorkspace.fromRows(
      students: students,
      teachers: teachers,
      classes: classes,
      submissions: submissions,
      profilesById: profilesById,
    );
  }

  Future<void> approveStudent(String studentId) async {
    // profiles_guard deliberately permits changing only the approved flag.
    final result = await _client
        .from('profiles')
        .update({'approved': true})
        .eq('id', studentId)
        .select('id')
        .maybeSingle();
    if (result == null) {
      throw StateError('The account was not found or could not be approved.');
    }
  }

  Future<void> promoteTeacher(String email) async {
    await _client.rpc('assign_teacher', params: {'p_email': email.trim()});
  }

  Future<void> createClass(String name) async {
    await _client.rpc('create_class', params: {'p_name': name.trim()});
  }

  Future<void> assignTeacherToClass({
    required int classId,
    required String teacherId,
  }) async {
    await _client.rpc(
      'assign_teacher_to_class',
      params: {'p_class': classId, 'p_teacher': teacherId},
    );
  }

  Future<void> assignStudentToTeacher({
    required String studentId,
    required String teacherId,
  }) async {
    await _client.rpc(
      'assign_student_to_teacher',
      params: {'p_student': studentId, 'p_teacher': teacherId},
    );
  }

  Future<void> createAssignment({
    required String adminId,
    required String title,
    required String instructions,
    required String kind,
    required String skill,
    required int targetCount,
    required int? classId,
    required DateTime? dueAt,
  }) async {
    await _client.from('assignments').insert({
      'created_by': adminId,
      'title': title.trim(),
      'instructions': instructions.trim(),
      'kind': kind,
      'skill': skill.trim(),
      'target_count': targetCount,
      'class_id': classId,
      'due_at': dueAt?.toUtc().toIso8601String(),
      'archived': false,
    });
  }

  Future<void> createAnnouncement({
    required String adminId,
    required String title,
    required String body,
    required int? classId,
    required bool pinned,
    required DateTime? expiresAt,
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 120) {
      throw ArgumentError('Announcement title must be 1–120 characters.');
    }
    if (cleanBody.isEmpty || cleanBody.length > 2000) {
      throw ArgumentError('Announcement message must be 1–2000 characters.');
    }
    await _client.from('announcements').insert({
      'created_by': adminId,
      'title': cleanTitle,
      'body': cleanBody,
      'class_id': classId,
      'pinned': pinned,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    });
  }

  Future<void> reviewSubmission({
    required int submissionId,
    required String adminId,
    required String status,
    required String note,
    required int rating,
  }) async {
    if (!const ['reviewed', 'flagged'].contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    await _client
        .from('submissions')
        .update({
          'review_status': status,
          'review_note': note.trim().isEmpty ? null : note.trim(),
          'rating': rating.clamp(1, 5).toInt(),
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'reviewed_by': adminId,
          // Keep feedback unread so the student receives it on the next sync.
          'student_seen': false,
        })
        .eq('id', submissionId)
        .select('id')
        .single();
  }
}

List<Map<String, dynamic>> _adminRows(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}
