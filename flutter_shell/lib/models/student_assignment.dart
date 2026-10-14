import 'dart:math' as math;

class StudentAssignment {
  const StudentAssignment({
    required this.id,
    required this.className,
    required this.title,
    required this.instructions,
    required this.kind,
    required this.skill,
    required this.targetCount,
    required this.dueAt,
    required this.done,
    required this.correct,
  });

  final int id;
  final String? className;
  final String title;
  final String instructions;
  final String kind;
  final String skill;
  final int targetCount;
  final DateTime? dueAt;
  final int done;
  final int correct;

  bool get isCompleted => targetCount > 0 && done >= targetCount;
  int get remaining => math.max(0, targetCount - done);
  double get progressRatio =>
      targetCount <= 0 ? 0 : (done / targetCount).clamp(0.0, 1.0).toDouble();

  bool isOverdue({DateTime? now}) =>
      !isCompleted && dueAt != null && dueAt!.isBefore(now ?? DateTime.now());

  bool get supportsInAppPractice {
    if (kind.trim().toLowerCase() != 'practice') return false;
    final value = skill.trim().toLowerCase();
    return value.isEmpty ||
        value == 'any' ||
        value.contains('grammar') ||
        value.contains('vocab') ||
        value.contains('word') ||
        value.contains('article') ||
        value == 'de-en' ||
        value == 'en-de';
  }

  factory StudentAssignment.fromJson(
    Map<String, dynamic> row, {
    Map<String, dynamic>? progress,
  }) {
    final nested = row['classes'];
    final classInfo = nested is Map ? Map<String, dynamic>.from(nested) : null;
    final target = math.max(1, _asInt(row['target_count'], 20));
    final done = math.max(0, _asInt(progress?['done']));
    final correct = math.max(0, _asInt(progress?['correct']));

    return StudentAssignment(
      id: _asInt(row['id']),
      className: classInfo?['name'] as String?,
      title: row['title'] as String? ?? 'Assignment',
      instructions: row['instructions'] as String? ?? '',
      kind: row['kind'] as String? ?? 'practice',
      skill: row['skill'] as String? ?? 'any',
      targetCount: target,
      dueAt: DateTime.tryParse(row['due_at']?.toString() ?? ''),
      done: math.min(done, target),
      correct: math.min(correct, math.min(done, target)),
    );
  }
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
