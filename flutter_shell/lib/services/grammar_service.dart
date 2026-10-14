import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/grammar_lesson.dart';

class GrammarService {
  const GrammarService();

  Future<List<GrammarSection>> loadSections() async {
    final content = await rootBundle.loadString('assets/grammar-data.json');
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Grammar data has an unexpected format.');
    }

    final rawSections = decoded['sections'];
    if (rawSections is! List) {
      throw const FormatException('Grammar sections are missing.');
    }

    final sections = rawSections
        .whereType<Map>()
        .map((section) => GrammarSection.fromJson(
              Map<String, dynamic>.from(section),
            ))
        .where((section) => section.lessons.isNotEmpty)
        .toList();

    if (sections.isEmpty) {
      throw const FormatException('No grammar lessons were loaded.');
    }

    return sections;
  }
}
