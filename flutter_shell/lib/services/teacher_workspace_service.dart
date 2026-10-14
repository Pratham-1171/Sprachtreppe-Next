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
}
