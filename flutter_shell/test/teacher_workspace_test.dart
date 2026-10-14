import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/models/teacher_workspace.dart';

void main() {
  test('parses teacher-scoped classes, work, announcements, and students', () {
    final workspace = TeacherWorkspace.fromRpc(
      classroom: {
        'classes': [
          {'id': 3, 'name': 'A2 Evening', 'archived': false},
        ],
        'assignments': [
          {
            'id': 17,
            'class_id': 3,
            'title': 'Dative practice',
            'kind': 'practice',
            'skill': 'grammar',
            'target_count': 12,
          },
        ],
        'announcements': [
          {
            'id': 8,
            'class_id': 3,
            'title': 'Exam revision',
            'body': 'Review dative and accusative.',
            'pinned': true,
          },
        ],
      },
      students: [
        {
          'id': 'student-uuid',
          'full_name': 'Alex Student',
          'email': 'alex@example.test',
          'approved': true,
          'assignment_count': 4,
          'completed_assignments': 2,
          'done': 16,
          'correct': 12,
          'last_activity': '2026-10-12T08:00:00Z',
        },
      ],
    );

    expect(workspace.classes.single.name, 'A2 Evening');
    expect(workspace.assignments.single.classId, 3);
    expect(workspace.assignments.single.targetCount, 12);
    expect(workspace.announcements.single.pinned, isTrue);
    expect(workspace.students.single.fullName, 'Alex Student');
    expect(workspace.students.single.completedAssignments, 2);
    expect(workspace.students.single.done, 16);
  });

  test('handles empty RPC results without throwing', () {
    final workspace = TeacherWorkspace.fromRpc(
      classroom: <String, dynamic>{},
      students: const [],
    );
    expect(workspace.classes, isEmpty);
    expect(workspace.assignments, isEmpty);
    expect(workspace.announcements, isEmpty);
    expect(workspace.students, isEmpty);
  });
}
