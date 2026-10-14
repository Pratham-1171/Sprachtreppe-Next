import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sprachtreppe_flutter/services/offline_assignment_progress_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('OfflineAssignmentProgressService', () {
    test('persists progress and merges it monotonically per assignment', () async {
      final service = OfflineAssignmentProgressService('student-a');
      await service.recordProgress(assignmentId: 7, done: 8, correct: 5);
      await service.recordProgress(assignmentId: 7, done: 12, correct: 9);

      final pending = await service.loadOne(7);
      expect(pending?.done, 12);
      expect(pending?.correct, 9);

      final payload = await service.loadForSync();
      expect(payload['7'], {'done': 12, 'ok': 9});
    });

    test('clears only the synced snapshot and keeps newer progress queued', () async {
      final service = OfflineAssignmentProgressService('student-a');
      await service.recordProgress(assignmentId: 7, done: 8, correct: 5);
      final sent = await service.loadForSync();

      await service.recordProgress(assignmentId: 7, done: 10, correct: 7);
      await service.clearSynced(sent);

      final latest = await service.loadOne(7);
      expect(latest?.done, 10);
      expect(latest?.correct, 7);
    });

    test('clears an unchanged server-confirmed snapshot', () async {
      final service = OfflineAssignmentProgressService('student-a');
      await service.recordProgress(assignmentId: 12, done: 20, correct: 14);
      await service.clearSynced(await service.loadForSync());

      expect(await service.loadAll(), isEmpty);
      expect(await service.loadForSync(), isEmpty);
    });

    test('keeps progress isolated per student', () async {
      final first = OfflineAssignmentProgressService('student-one');
      final second = OfflineAssignmentProgressService('student-two');
      await first.recordProgress(assignmentId: 3, done: 5, correct: 4);

      expect((await first.loadForSync()).keys, contains('3'));
      expect(await second.loadForSync(), isEmpty);
    });

    test('rejects invalid assignment progress values', () async {
      final service = OfflineAssignmentProgressService('student-a');
      expect(
        () => service.recordProgress(assignmentId: 0, done: 1, correct: 1),
        throwsArgumentError,
      );
      expect(
        () => service.recordProgress(assignmentId: 4, done: 2, correct: 3),
        throwsArgumentError,
      );
    });
  });
}
