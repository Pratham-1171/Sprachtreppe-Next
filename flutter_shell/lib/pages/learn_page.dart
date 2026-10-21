import 'package:flutter/material.dart';

import 'course_page.dart';
import 'grammar_page.dart';
import 'vocabulary_page.dart';

class LearnPage extends StatefulWidget {
  const LearnPage({super.key, required this.userId});

  final String userId;

  @override
  State<LearnPage> createState() => _LearnPageState();
}

class _LearnPageState extends State<LearnPage> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.menu_book_outlined),
                label: Text('Course'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.translate),
                label: Text('Words'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.rule_outlined),
                label: Text('Grammar'),
              ),
            ],
            selected: {_section},
            onSelectionChanged: (value) => setState(() => _section = value.first),
            showSelectedIcon: false,
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _section,
            children: [
              CoursePage(userId: widget.userId),
              VocabularyPage(userId: widget.userId),
              GrammarPage(userId: widget.userId),
            ],
          ),
        ),
      ],
    );
  }
}
