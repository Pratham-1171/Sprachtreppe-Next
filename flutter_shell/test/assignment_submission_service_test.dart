import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/models/student_assignment.dart';
import 'package:sprachtreppe_flutter/services/assignment_submission_service.dart';

void main() {
  test('builds the secure progress payload for a written response', () {
    final assignment = StudentAssignment.fromJson(
      {
        'id': 42,
        'title': 'Write an informal email',
        'instructions': 'Write 80 words.',
        'kind': 'writing',
        'skill': 'writing',
        'target_count': 1,
      },
      progress: {'done': 0, 'correct': 0},
    );

    final payload = buildAssignmentResponsePayload(
      assignment: assignment,
      response: '  Hallo Anna! Wie geht es dir?  ',
      submittedAt: DateTime.utc(2026, 10, 14, 8),
    );

    expect(payload['summary'], isA<Map>());
    expect(payload['assignments'], contains('42'));
    expect((payload['assignments'] as Map)['42']['done'], 1);
    expect((payload['assignment_response'] as Map)['text'], 'Hallo Anna! Wie geht es dir?');
    expect(
      (payload['summary'] as Map)['source'],
      'flutter_assignment_response',
    );
  });
}
