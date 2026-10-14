import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sprachtreppe_flutter/services/progress_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('records rounds and calculates accuracy plus study streaks', () async {
    final preferences = await SharedPreferences.getInstance();
    final service = ProgressService('student-progress-test', preferences: preferences);
    final now = DateTime(2026, 10, 14, 12);

    await service.recordSession(
      mode: 'Grammar',
      level: 'A1',
      correct: 8,
      total: 10,
      completedAt: DateTime(2026, 10, 12, 9),
    );
    await service.recordSession(
      mode: 'Articles',
      level: 'A1',
      correct: 6,
      total: 10,
      completedAt: DateTime(2026, 10, 13, 9),
    );
    await service.recordSession(
      mode: 'German → English',
      level: 'A2',
      correct: 10,
      total: 10,
      completedAt: now,
    );

    final stats = await service.loadStats(now: now);
    expect(stats.totalSessions, 3);
    expect(stats.totalQuestions, 30);
    expect(stats.correctAnswers, 24);
    expect(stats.accuracyPercent, 80);
    expect(stats.currentStreak, 3);
    expect(stats.bestStreak, 3);
    expect(stats.sessionsToday, 1);
  });

  test('keeps study history separate for different students', () async {
    final preferences = await SharedPreferences.getInstance();
    final first = ProgressService('student-one', preferences: preferences);
    final second = ProgressService('student-two', preferences: preferences);

    await first.recordSession(
      mode: 'Grammar',
      level: 'A1',
      correct: 1,
      total: 2,
      completedAt: DateTime(2026, 10, 14),
    );

    expect((await first.loadStats()).totalSessions, 1);
    expect((await second.loadStats()).totalSessions, 0);
  });
}
