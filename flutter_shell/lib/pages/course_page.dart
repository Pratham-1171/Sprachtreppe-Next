import 'package:flutter/material.dart';

import '../models/course_module.dart';
import 'grammar_page.dart';
import '../services/course_service.dart';

class CoursePage extends StatefulWidget {
  const CoursePage({super.key, required this.userId});

  final String userId;

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  final _service = const CourseService();
  String _level = 'All';

  List<CourseModule> get _filtered => _level == 'All'
      ? _service.modules
      : _service.modules.where((module) => module.level == _level).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 500 ? 16.0 : 24.0;
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 28),
            children: [
              Text('Course', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Learn German from A1 to B1 with focused grammar and practical progression.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'All', label: Text('All')),
                  ButtonSegment(value: 'A1', label: Text('A1')),
                  ButtonSegment(value: 'A2', label: Text('A2')),
                  ButtonSegment(value: 'B1', label: Text('B1')),
                ],
                selected: {_level},
                onSelectionChanged: (value) => setState(() => _level = value.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 16),
              ..._filtered.map((module) => _ModuleCard(module: module, userId: widget.userId)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.construction_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Course migration is incremental. The legacy lesson engine stays available until these Flutter lessons are fully migrated and verified.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.userId});

  final CourseModule module;
  final String userId;

  void _openTopic(BuildContext context, String topic) {
    final query = _grammarQueryForTopic(topic);
    if (query == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A dedicated Flutter lesson for "$topic" is not available yet. Showing the current ${module.level} lesson library.'),
        ),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('${module.level} grammar')),
          body: GrammarPage(
            userId: userId,
            initialLevel: module.level,
            initialQuery: query ?? '',
          ),
        ),
      ),
    );
  }

  String? _grammarQueryForTopic(String topic) {
    final value = topic.toLowerCase();
    if (value.contains('sein') && value.contains('haben')) return 'sein & haben';
    if (value.contains('personal pronouns') || value.contains('verb endings')) {
      return 'Präsens (regular)';
    }
    if (value.contains('articles') || value.contains('nominative')) return 'Articles';
    if (value.contains('accusative')) return 'Akkusativ';
    if (value.contains('dative')) return 'Dativ';
    if (value.contains('modal verbs') && value.contains('präteritum')) {
      return 'Modal verbs in Präteritum';
    }
    if (value.contains('modal verbs')) return 'Modal verbs';
    if (value.contains('questions') && value.contains('word order')) return 'Word order';
    if (value.contains('word order')) return 'Word order';
    if (value.contains('perfekt')) return 'Perfekt';
    if (value.contains('weil')) return 'weil';
    if (value.contains('dass')) return 'dass';
    if (value.contains('wenn') || value.contains('als')) return 'als vs. wenn';
    if (value.contains('indirect') && value.contains('question')) return 'Indirect W-questions';
    if (value.contains('deshalb')) return 'deshalb';
    if (value.contains('trotzdem')) return 'trotzdem';
    if (value.contains('konjunktiv ii') && module.level == 'B1') {
      return 'Konjunktiv II hypothetical';
    }
    if (value.contains('konjunktiv ii') || value.contains('polite') || value.contains('requests')) {
      return 'könnte';
    }
    if (value.contains('adjective endings')) return 'Adjective endings';
    if (value.contains('relative clause')) return 'Relative clauses';
    if (value.contains('passive')) return 'Passive voice';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('${module.level} · ${module.title}'),
        subtitle: Text(module.description),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Topics', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          ...module.topics.map(
            (topic) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle_outline, size: 20, color: theme.colorScheme.primary),
              title: Text(topic),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openTopic(context, topic),
            ),
          ),
        ],
      ),
    );
  }
}
