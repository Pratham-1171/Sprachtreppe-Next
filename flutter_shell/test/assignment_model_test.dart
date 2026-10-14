import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/models/student_assignment.dart';

void main() {
  test('maps assignment details and progress', () {
    final item = StudentAssignment.fromJson(
      {
        'id': 7,
        'classes': {'name': 'A2 Evening Class'},
        'title': 'Practise dative',
        'instructions': 'Complete the quiz.',
        'kind': 'practice',
        'skill': 'grammar',
        'target_count': 10,
        'due_at': '2026-10-20T15:00:00Z',
      },
      progress: {'done': 4, 'correct': 3},
    );
    expect(item.id, 7);
    expect(item.className, 'A2 Evening Class');
    expect(item.done, 4);
    expect(item.correct, 3);
    expect(item.remaining, 6);
    expect(item.progressRatio, 0.4);
    expect(item.isCompleted, isFalse);
    expect(item.supportsInAppPractice, isTrue);
  });

  test('clamps saved progress to its assignment target', () {
    final item = StudentAssignment.fromJson(
      {'id': 9, 'title': 'Articles', 'kind': 'practice', 'skill': 'articles', 'target_count': 5},
      progress: {'done': 99, 'correct': 120},
    );
    expect(item.done, 5);
    expect(item.correct, 5);
    expect(item.remaining, 0);
    expect(item.progressRatio, 1);
    expect(item.isCompleted, isTrue);
  });

  test('reading and writing are not falsely treated as quiz submissions', () {
    final item = StudentAssignment.fromJson(
      {'id': 11, 'title': 'Write an email', 'kind': 'writing', 'skill': 'writing', 'target_count': 1},
    );
    expect(item.supportsInAppPractice, isFalse);
  });
}
