import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/teacher_workspace.dart';

class TeacherWorkspaceService {
  TeacherWorkspaceService(this._client);

  final SupabaseClient _client;

  Future<TeacherWorkspace> load() async {
    // These RPCs scope results to auth.uid() and enforce teacher/admin role checks.
    // Do not replace them with broad reads from profiles or class_members.
    final results = await Future.wait<dynamic>([
      _client.rpc('my_classroom'),
      _client.rpc('my_students'),
    ]);
    return TeacherWorkspace.fromRpc(
      classroom: results[0],
      students: results[1],
    );
  }

  Future<void> createAnnouncement({
    required int classId,
    required String title,
    required String body,
    required bool pinned,
    required DateTime? expiresAt,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in again before publishing.');
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 120) {
      throw ArgumentError('Announcement title must be 1–120 characters.');
    }
    if (cleanBody.isEmpty || cleanBody.length > 2000) {
      throw ArgumentError('Announcement body must be 1–2000 characters.');
    }

    // RLS requires a teacher role, created_by = auth.uid(), and a class
    // assigned to this teacher. Never bypass this with a privileged key.
    await _client.from('announcements').insert({
      'class_id': classId,
      'title': cleanTitle,
      'body': cleanBody,
      'pinned': pinned,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'created_by': userId,
    });
  }
}
