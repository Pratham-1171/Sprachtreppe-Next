class VocabularyWord {
  const VocabularyWord({
    required this.number,
    required this.article,
    required this.german,
    required this.english,
    required this.topic,
    required this.level,
  });

  final int number;
  final String article;
  final String german;
  final String english;
  final String topic;
  final String level;

  String get displayGerman => article == '-' || article.isEmpty ? german : '$article $german';
}
