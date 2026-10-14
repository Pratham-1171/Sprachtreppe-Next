import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sprachtreppe_flutter/models/student_assignment.dart';
import 'package:sprachtreppe_flutter/services/offline_assignment_submission_queue_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  StudentAssignment assignment({int id = 42, String title = 'Write an email'}) {
    return StudentAssignment(
      id: id,
      className: 'A2 class',
      title: title,
      instructions: 'Write a short email.',
      kind: 'writing',
      skill: 'writing',
      targetCount: 1,
      dueAt: null,
      done: 0,
      correct: 0,
    );
  }

  group('OfflineAssignmentSubmissionQueueService', () {
    test('persists a written response with a stable client ID and valid payload', () async {
      final queue = OfflineAssignmentSubmissionQueueService('student-a');
      final first = await queue.enqueue(
        assignment: assignment(),
        response: '  Hallo Anna!  ',
      );
      final restored = await queue.loadOne(42);

      expect(restored, isNotNull);
      expect(restored!.clientId, first.clientId);
      expect(restored.response, 'Hallo Anna!');
      expect(restored.toPayload()['summary'], isA<Map>());
      expect(
        (restored.toPayload()['assignment_response'] as Map)['text'],
        'Hallo Anna!',
      );
      expect((restored.toPayload()['assignments'] as Map)['42']['done'], 1);
    });

    test('reuses an ID for identical text but rotates it when text changes', () async {
      final queue = OfflineAssignmentSubmissionQueueService('student-a');
      final first = await queue.enqueue(
        assignment: assignment(),
        response: 'First response',
      );
      final retry = await queue.enqueue(
        assignment: assignment(),
        response: 'First response',
      );
      final edited = await queue.enqueue(
        assignment: assignment(),
        response: 'Revised response',
      );

      expect(retry.clientId, first.clientId);
      expect(edited.clientId, isNot(first.clientId));
      expect((await queue.loadOne(42))?.response, 'Revised response');
    });

    test('clears only a server-confirmed snapshot and keeps a newer response', () async {
      final queue = OfflineAssignmentSubmissionQueueService('student-a');
      final sent = await queue.enqueue(
        assignment: assignment(),
        response: 'Older response',
      );
      await queue.enqueue(
        assignment: assignment(),
        response: 'Newer response',
      );

      await queue.clearSynced(sent);

      expect((await queue.loadOne(42))?.response, 'Newer response');
    });

    test('clears the matching local draft after a successful sync', () async {
      const key = 'sprachtreppe_assignment_draft_v1_student-a_42';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, 'Same response');

      final queue = OfflineAssignmentSubmissionQueueService('student-a');
      final sent = await queue.enqueue(
        assignment: assignment(),
        response: 'Same response',
      );
      await queue.clearSynced(sent);

      expect(await queue.loadAll(), isEmpty);
      expect(prefs.containsKey(key), isFalse);
    });

    test('does not delete a newer local draft', () async {
      const key = 'sprachtreppe_assignment_draft_v1_student-a_42';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, 'Newer draft');

      final queue = OfflineAssignmentSubmissionQueueService('student-a');
      final sent = await queue.enqueue(
        assignment: assignment(),
        response: 'Queued response',
      );
      await queue.clearSynced(sent);

      expect(prefs.getString(key), 'Newer draft');
    });

    test('keeps responses isolated per student', () async {
      final first = OfflineAssignmentSubmissionQueueService('student-one');
      final second = OfflineAssignmentSubmissionQueueService('student-two');
      await first.enqueue(
        assignment: assignment(),
        response: 'Private response',
      );

      expect((await first.loadAll()), hasLength(1));
      expect(await second.loadAll(), isEmpty);
    });

    test('rejects blank or overlong responses', () async {
      final queue = OfflineAssignmentSubmissionQueueService('student-a');
      expect(
        () => queue.enqueue(assignment: assignment(), response: '  '),
        throwsArgumentError,
      );
      expect(
        () => queue.enqueue(
          assignment: assignment(),
          response: List.filled(5001, 'a').join(),
        ),
        throwsArgumentError,
      );
    });
  });
}
