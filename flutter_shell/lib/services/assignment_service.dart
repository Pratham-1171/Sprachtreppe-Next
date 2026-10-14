import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student_assignment.dart';

class AssignmentService {
  AssignmentService(this._client);

  final SupabaseClient _client;

  Future<List<StudentAssignment>> loadForStudent(String studentId) async {
    // RLS on assignments_select is the access boundary for student visibility.
    final rawRows = await _client
        .from('assignments')
        .select(
          'id, class_id, title, instructions, kind, skill, target_count, '
          'due_at, created_at, classes(name)',
        )
        .eq('archived', false)
        .order('created_at', ascending: false)
        .limit(100);

    final rows = rawRows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final ids = rows
        .map((row) => row['id'])
        .whereType<num>()
        .map((id) => id.toInt())
        .toList();
    final progressById = <int, Map<String, dynamic>>{};

    if (ids.isNotEmpty) {
      final rawProgress = await _client
          .from('assignment_progress')
          .select('assignment_id, done, correct')
          .eq('student_id', studentId)
          .inFilter('assignment_id', ids);
      for (final value in rawProgress as List) {
        if (value is! Map) continue;
        final row = Map<String, dynamic>.from(value);
        final rawId = row['assignment_id'];
        if (rawId is num) progressById[rawId.toInt()] = row;
      }
    }

    return rows.map((row) {
      final rawId = row['id'];
      final id = rawId is num ? rawId.toInt() : int.tryParse(rawId.toString()) ?? 0;
      return StudentAssignment.fromJson(row, progress: progressById[id]);
    }).toList();
  }
}
