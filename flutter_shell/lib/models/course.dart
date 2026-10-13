class Course {
  const Course({
    required this.id,
    required this.level,
    required this.title,
    required this.subtitle,
    required this.lessons,
  });

  final String id;
  final String level;
  final String title;
  final String subtitle;
  final List<Lesson> lessons;
}

class Lesson {
  const Lesson({
    required this.id,
    required this.number,
    required this.title,
    required this.topic,
  });

  final String id;
  final int number;
  final String title;
  final String topic;
}
