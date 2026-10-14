import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/services/assignment_service.dart';

void main() {
  group('AssignmentService cache serialization', () {
    test('round-trips assignment details and saved progress', () {
      final encoded = AssignmentService.encodeCachedRows(
        [
          {
            'id': 7,
            'title': 'Practise dative',
            'instructions': 'Complete the quiz.',
            'kind': 'practice',
            'skill': 'grammar',
            'target_count': 10,
            'classes': {'name': 'A2 Evening Class'},
            'due_at': '2026-10-20T15:00:00Z',
          },
        ],
        const {
          7: {'assignment_id': 7, 'done': 4, 'correct': 3},
        },
      );

      final items = AssignmentService.decodeCachedRows(encoded);
      expect(items, hasLength(1));
      expect(items.single.title, 'Practise dative');
      expect(items.single.className, 'A2 Evening Class');
      expect(items.single.done, 4);
      expect(items.single.correct, 3);
      expect(items.single.remaining, 6);
    });

    test('does not invent progress when no cached progress exists', () {
      final encoded = AssignmentService.encodeCachedRows(
        [
          {
            'id': 9,
            'title': 'Write an email',
            'kind': 'writing',
            'skill': 'writing',
            'target_count': 1,
          },
        ],
        const {},
      );
      final item = AssignmentService.decodeCachedRows(encoded).single;
      expect(item.done, 0);
      expect(item.correct, 0);
    });

    test('recognises common connectivity failures only', () {
      expect(
        AssignmentService.isConnectivityFailure(
          Exception('SocketException: Failed host lookup'),
        ),
        isTrue,
      );
      expect(
        AssignmentService.isConnectivityFailure(
          Exception('No address associated with hostname'),
        ),
        isTrue,
      );
      expect(
        AssignmentService.isConnectivityFailure(Exception('permission denied')),
        isFalse,
      );
      expect(
        AssignmentService.isConnectivityFailure(Exception('invalid JWT')),
        isFalse,
      );
    });

    test('rejects invalid cached payload instead of returning misleading data', () {
      expect(
        () => AssignmentService.decodeCachedRows('{bad json'),
        throwsFormatException,
      );
      expect(
        () => AssignmentService.decodeCachedRows('{"rows": {}}'),
        throwsFormatException,
      );
    });
  });
}
