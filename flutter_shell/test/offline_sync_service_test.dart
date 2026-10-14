import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/services/offline_sync_service.dart';

void main() {
  group('OfflineSyncService.sessionSnapshot', () {
    final completedAt = DateTime.utc(2026, 10, 14, 9);
    final firstSession = StudySession(
      completedAt: completedAt,
      mode: 'Quiz',
      level: 'A1',
      correct: 4,
      total: 5,
    );

    test('is stable for an unchanged local snapshot', () {
      final sessions = [firstSession];
      final stats = ProgressStats.fromSessions(sessions, now: completedAt);
      expect(
        OfflineSyncService.sessionSnapshot(sessions, stats),
        OfflineSyncService.sessionSnapshot(sessions, stats),
      );
    });

    test('changes when a new practice session is added', () {
      final sessions = [firstSession];
      final firstStats = ProgressStats.fromSessions(sessions, now: completedAt);
      final firstSnapshot = OfflineSyncService.sessionSnapshot(sessions, firstStats);
      final updatedSessions = [
        StudySession(
          completedAt: completedAt.add(const Duration(minutes: 10)),
          mode: 'Grammar',
          level: 'A2',
          correct: 3,
          total: 4,
        ),
        ...sessions,
      ];
      final updatedStats = ProgressStats.fromSessions(
        updatedSessions,
        now: completedAt.add(const Duration(minutes: 10)),
      );
      expect(
        OfflineSyncService.sessionSnapshot(updatedSessions, updatedStats),
        isNot(firstSnapshot),
      );
    });
  });

  group('OfflineSyncService.isSyncDue', () {
    final now = DateTime.utc(2026, 10, 14, 10);

    test('requires a first sync when there is no previous timestamp', () {
      expect(OfflineSyncService.isSyncDue(null, now: now), isTrue);
    });

    test('does not require a sync before seven full days have elapsed', () {
      final sixDaysLater = now.subtract(const Duration(seconds: 1));
      final lastSync = sixDaysLater.subtract(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      expect(
        OfflineSyncService.isSyncDue(lastSync, now: sixDaysLater),
        isFalse,
      );
    });

    test('requires a sync at exactly seven days', () {
      final lastSync = now.subtract(const Duration(days: 7));
      expect(OfflineSyncService.isSyncDue(lastSync, now: now), isTrue);
    });

    test('requires a sync after seven days', () {
      final lastSync = now.subtract(const Duration(days: 8));
      expect(OfflineSyncService.isSyncDue(lastSync, now: now), isTrue);
    });
  });
}
