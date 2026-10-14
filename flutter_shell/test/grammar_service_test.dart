import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/services/grammar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled grammar library contains A1, A2, and B1', () async {
    const service = GrammarService();
    final sections = await service.loadSections();

    expect(
      sections.map((section) => section.level).toList(),
      equals(['A1', 'A2', 'B1']),
    );
    expect(
      sections.fold<int>(0, (total, section) => total + section.lessons.length),
      32,
    );
  });

  test('every bundled grammar lesson has examples and a quick check', () async {
    const service = GrammarService();
    final sections = await service.loadSections();

    for (final section in sections) {
      for (final lesson in section.lessons) {
        expect(lesson.examples, isNotEmpty, reason: lesson.title);
        expect(lesson.exercise, isNotNull, reason: lesson.title);
        expect(lesson.exercise!.options, isNotEmpty, reason: lesson.title);
        expect(
          lesson.exercise!.correctIndex,
          inInclusiveRange(0, lesson.exercise!.options.length - 1),
          reason: lesson.title,
        );
      }
    }
  });
}
