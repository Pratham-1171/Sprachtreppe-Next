import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/models/admin_workspace.dart';

void main() {
  test('parses overview, relationships and review submissions', () {
    final workspace = AdminWorkspace.fromRows(
      students: [
        {
          'id': 'student-id',
          'full_name': 'Mira Student',
          'email': 'mira@example.test',
          'approved': false,
          'teachers': [{'id': 'teacher-id', 'name': 'Herr Teacher'}],
          'classes': [{'id': 4, 'name': 'A2 evening'}],
          'assignment_count': 3,
          'completed_assignments': 1,
          'done': 12,
          'correct': 9,
          'last_activity': '2026-10-12T08:00:00Z',
          'pending_submissions': 1,
        },
      ],
      teachers: [
        {'id': 'teacher-id', 'full_name': 'Herr Teacher', 'email': 'teacher@example.test'},
      ],
      classes: [
        {'id': 4, 'name': 'A2 evening'},
      ],
      submissions: [
        {
          'id': 50,
          'student_id': 'student-id',
          'created_at': '2026-10-14T08:00:00Z',
          'summary': {
            'source': 'flutter_assignment_response',
            'assignment_title': 'Write an email',
          },
          'payload': {
            'assignment_response': {'title': 'Write an email', 'text': 'Hallo Anna!'},
          },
          'review_status': 'pending',
        },
      ],
      profilesById: {
        'student-id': {'id': 'student-id', 'full_name': 'Mira Student', 'email': 'mira@example.test'},
      },
    );

    expect(workspace.students.single.approved, isFalse);
    expect(workspace.students.single.teachers.single.name, 'Herr Teacher');
    expect(workspace.students.single.classes.single.id, '4');
    expect(workspace.teachers.single.email, 'teacher@example.test');
    expect(workspace.classes.single.id, 4);
    expect(workspace.submissions.single.studentName, 'Mira Student');
    expect(workspace.submissions.single.writtenResponse, 'Hallo Anna!');
    expect(workspace.submissions.single.assignmentTitle, 'Write an email');
  });

  test('handles missing optional fields safely', () {
    final workspace = AdminWorkspace.fromRows(
      students: [{'id': 'one', 'full_name': 'Student'}],
      teachers: const [],
      classes: const [],
      submissions: [
        {'id': 1, 'student_id': 'unknown', 'summary': {}, 'payload': {}, 'review_status': 'pending'},
      ],
      profilesById: const {},
    );

    expect(workspace.students.single.approved, isFalse);
    expect(workspace.students.single.pendingSubmissions, 0);
    expect(workspace.submissions.single.studentName, 'Student');
    expect(workspace.submissions.single.writtenResponse, isNull);
    expect(workspace.submissions.single.assignmentTitle, 'Learning activity');
  });
}
