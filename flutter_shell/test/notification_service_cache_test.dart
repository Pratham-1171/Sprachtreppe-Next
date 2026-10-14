import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/services/notification_service.dart';

void main() {
  group('Notification cache', () {
    test('round-trips read and unread notifications', () {
      final notifications = [
        AppNotification(
          id: 9,
          kind: 'announcement',
          title: 'Exam revision',
          body: 'Review chapters 3–5.',
          link: '#/notifications',
          createdAt: DateTime.utc(2026, 10, 14, 9),
          readAt: null,
        ),
        AppNotification(
          id: 10,
          kind: 'assignment_assigned',
          title: 'New assignment',
          body: 'Write an email.',
          link: '#/assignments',
          createdAt: DateTime.utc(2026, 10, 14, 10),
          readAt: DateTime.utc(2026, 10, 14, 11),
        ),
      ];

      final restored = NotificationService.decodeCachedNotifications(
        NotificationService.encodeCachedNotifications(notifications),
      );

      expect(restored, hasLength(2));
      expect(restored.first.id, 9);
      expect(restored.first.isRead, isFalse);
      expect(restored.first.body, 'Review chapters 3–5.');
      expect(restored.last.id, 10);
      expect(restored.last.isRead, isTrue);
      expect(restored.last.readAt, DateTime.utc(2026, 10, 14, 11));
    });

    test('rejects malformed cache data', () {
      expect(
        () => NotificationService.decodeCachedNotifications('{bad json'),
        throwsFormatException,
      );
      expect(
        () => NotificationService.decodeCachedNotifications('{"rows": []}'),
        throwsFormatException,
      );
    });

    test('only treats connection failures as cache fallback candidates', () {
      expect(
        NotificationService.isConnectivityFailure(
          Exception('SocketException: Failed host lookup'),
        ),
        isTrue,
      );
      expect(
        NotificationService.isConnectivityFailure(
          Exception('Network is unreachable'),
        ),
        isTrue,
      );
      expect(
        NotificationService.isConnectivityFailure(Exception('permission denied')),
        isFalse,
      );
      expect(
        NotificationService.isConnectivityFailure(Exception('invalid JWT')),
        isFalse,
      );
    });
  });
}
