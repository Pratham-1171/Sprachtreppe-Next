import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student_assignment.dart';

Map<String, dynamic> buildAssignmentResponsePayload({
  required StudentAssignment assignment,
  required String response,
  required DateTime submittedAt,
}) {
  final timestamp = submittedAt.toUtc().toIso8601String();
  return {
    'summary': {
      'source': 'flutter_assignment_response',
      'assignment_id': assignment.id,
      'assignment_title': assignment.title,
      'kind': assignment.kind,
      'skill': assignment.skill,
      'submitted_at': timestamp,
    },
    'assignment_response': {
      'assignment_id': assignment.id,
      'title': assignment.title,
      'kind': assignment.kind,
      'skill': assignment.skill,
      'text': response.trim(),
      'submitted_at': timestamp,
    },
    'assignments': {
      assignment.id.toString(): {
        'done': assignment.targetCount,
        'ok': assignment.correct,
      },
    },
  };
}

class AssignmentSubmissionService {
  AssignmentSubmissionService(this._client);

  final SupabaseClient _client;

  Future<void> submitResponse({
    required StudentAssignment assignment,
    required String response,
    required String clientId,
  }) async {
    final payload = buildAssignmentResponsePayload(
      assignment: assignment,
      response: response,
      submittedAt: DateTime.now(),
    );
    final result = await _client.rpc(
      'submit_progress',
      params: {
        'p_payload': payload,
        'p_client_id': clientId,
      },
    );

    if (result is Map && result['ok'] == false) {
      throw const FormatException('The server did not accept this submission.');
    }
  }
}
