class CourseModule {
  const CourseModule({
    required this.id,
    required this.level,
    required this.title,
    required this.description,
    required this.topics,
  });

  final String id;
  final String level;
  final String title;
  final String description;
  final List<String> topics;
}
