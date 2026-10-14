import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/services/offline_sync_service.dart';

void main() {
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
