import 'package:flutter/services.dart';

import '../models/vocabulary_word.dart';

class VocabularyService {
  const VocabularyService();

  static final RegExp _topicPattern = RegExp(
    r'\["([^"]+)","(A1|A2|B1)",`([\s\S]*?)`\]',
  );

  Future<List<VocabularyWord>> loadWords() async {
    final source = await rootBundle.loadString('assets/vocabulary-data.js');
    final words = <VocabularyWord>[];

    for (final match in _topicPattern.allMatches(source)) {
      final topic = match.group(1)!;
      final level = match.group(2)!;
      final raw = match.group(3)!;

      for (final line in raw.trim().split('\n')) {
        final parts = line.split('|');
        if (parts.length < 4) continue;
        final number = int.tryParse(parts[0].trim());
        if (number == null) continue;
        words.add(
          VocabularyWord(
            number: number,
            article: parts[1].trim(),
            german: parts[2].trim(),
            english: parts.sublist(3).join('|').trim(),
            topic: topic,
            level: level,
          ),
        );
      }
    }

    if (words.isEmpty) {
      throw StateError('Vocabulary data could not be parsed.');
    }
    return words;
  }
}
