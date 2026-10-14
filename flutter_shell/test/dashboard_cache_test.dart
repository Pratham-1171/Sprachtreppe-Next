import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/services/dashboard_service.dart';

void main() {
  group('Dashboard cache', () {
    test('round-trips classes, assignments and announcements', () {
      final original = DashboardData(
        classes: const [ClassSummary(id: 3, name: 'A2 Evening')],
        pendingAssignments: [
          AssignmentSummary(
            id: 17,
            title: 'Practise dative',
            skill: 'grammar',
            dueAt: DateTime.utc(2026, 10, 20, 15),
            targetCount: 10,
            done: 4,
            correct: 3,
            className: 'A2 Evening',
          ),
        ],
        completedAssignments: 2,
        unreadNotifications: 4,
        recentAnnouncements: [
          AnnouncementSummary(
            title: 'Exam revision',
            body: 'Review chapters 3–5.',
            createdAt: DateTime.utc(2026, 10, 14, 9),
            pinned: true,
          ),
        ],
      );

      final restored = DashboardData.fromCacheJson(
        jsonEncode(original.toCacheJson()),
      );

      expect(restored.classes.single.name, 'A2 Evening');
      expect(restored.pendingAssignments.single.done, 4);
      expect(restored.pendingAssignments.single.correct, 3);
      expect(restored.pendingAssignments.single.dueAt, original.pendingAssignments.single.dueAt);
      expect(restored.completedAssignments, 2);
      expect(restored.unreadNotifications, 4);
      expect(restored.recentAnnouncements.single.title, 'Exam revision');
      expect(restored.recentAnnouncements.single.pinned, isTrue);
    });

    test('rejects malformed dashboard cache', () {
      expect(
        () => DashboardData.fromCacheJson('{bad json'),
        throwsFormatException,
      );
      expect(
        () => DashboardData.fromCacheJson('[]'),
        throwsFormatException,
      );
    });

    test('only recognizes common connectivity failures', () {
      expect(
        isDashboardConnectivityFailure(
          Exception('SocketException: Failed host lookup'),
        ),
        isTrue,
      );
      expect(
        isDashboardConnectivityFailure(Exception('permission denied')),
        isFalse,
      );
    });
  });
}
