class GrammarSection {
  const GrammarSection({
    required this.level,
    required this.title,
    required this.lessons,
  });

  final String level;
  final String title;
  final List<GrammarLesson> lessons;

  factory GrammarSection.fromJson(Map<String, dynamic> json) {
    final items = json['lessons'] as List<dynamic>? ?? const [];
    return GrammarSection(
      level: json['level'] as String? ?? '',
      title: json['title'] as String? ?? '',
      lessons: items
          .whereType<Map>()
          .map((item) => GrammarLesson.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class GrammarLesson {
  const GrammarLesson({
    required this.level,
    required this.title,
    required this.explanation,
    required this.rule,
    required this.examples,
    required this.mistakes,
    required this.guide,
    required this.exercise,
  });

  final String level;
  final String title;
  final String explanation;
  final String rule;
  final List<List<String>> examples;
  final List<List<String>> mistakes;
  final GrammarGuide guide;
  final GrammarExercise? exercise;

  factory GrammarLesson.fromJson(Map<String, dynamic> json) {
    final guideJson = json['guide'];
    final exerciseJson = json['exercise'];
    return GrammarLesson(
      level: json['level'] as String? ?? '',
      title: json['title'] as String? ?? 'Grammar lesson',
      explanation: json['explanation'] as String? ?? '',
      rule: json['rule'] as String? ?? '',
      examples: _readPairs(json['examples']),
      mistakes: _readPairs(json['mistakes']),
      guide: guideJson is Map
          ? GrammarGuide.fromJson(Map<String, dynamic>.from(guideJson))
          : const GrammarGuide(),
      exercise: exerciseJson is Map
          ? GrammarExercise.fromJson(Map<String, dynamic>.from(exerciseJson))
          : null,
    );
  }

  static List<List<String>> _readPairs(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<List>()
        .map((pair) => pair.map((part) => part.toString()).toList())
        .where((pair) => pair.length >= 2)
        .toList();
  }
}

class GrammarGuide {
  const GrammarGuide({
    this.when = '',
    this.steps = const [],
    this.tip = '',
    this.contrast = '',
  });

  final String when;
  final List<String> steps;
  final String tip;
  final String contrast;

  factory GrammarGuide.fromJson(Map<String, dynamic> json) {
    return GrammarGuide(
      when: json['when'] as String? ?? '',
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((step) => step.toString())
          .toList(),
      tip: json['tip'] as String? ?? '',
      contrast: json['contrast'] as String? ?? '',
    );
  }
}

class GrammarExercise {
  const GrammarExercise({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  factory GrammarExercise.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>? ?? const [])
        .map((option) => option.toString())
        .toList();
    final rawIndex = json['correct'];
    final correctIndex = rawIndex is int ? rawIndex : int.tryParse('$rawIndex') ?? 0;
    return GrammarExercise(
      question: json['q'] as String? ?? 'Choose the correct answer.',
      options: options,
      correctIndex: options.isEmpty
          ? 0
          : correctIndex.clamp(0, options.length - 1),
      explanation: json['why'] as String? ?? '',
    );
  }
}
