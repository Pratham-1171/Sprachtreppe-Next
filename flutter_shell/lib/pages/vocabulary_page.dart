import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vocabulary_word.dart';
import '../services/learning_state_sync_service.dart';
import '../services/vocabulary_service.dart';

class VocabularyPage extends StatefulWidget {
  const VocabularyPage({super.key, required this.userId});

  final String userId;

  @override
  State<VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends State<VocabularyPage> {
  final _service = const VocabularyService();
  late Future<List<VocabularyWord>> _future;
  String _level = 'All';
  String _topic = 'All';
  String _query = '';
  Map<String, dynamic> _learningState = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _future = _service.loadWords();
    _loadSharedProgress();
  }

  Future<void> _loadSharedProgress() async {
    final sync = LearningStateSyncService(Supabase.instance.client, widget.userId);
    try {
      await sync.sync();
    } catch (_) {
      // Cached learning state remains available while offline.
    }
    final state = await sync.loadAggregateState();
    if (mounted) setState(() => _learningState = state);
  }

  Future<void> _reload() async {
    setState(() => _future = _service.loadWords());
    await _future;
    await _loadSharedProgress();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<VocabularyWord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(onRetry: _reload);
        }

        final words = snapshot.data ?? const <VocabularyWord>[];
        final rawMastery = _learningState['vocabularyMastery'];
        final mastery = rawMastery is Map ? rawMastery : <dynamic, dynamic>{};
        final rawCourseState = _learningState['courseState'];
        final courseState = rawCourseState is Map ? rawCourseState : <dynamic, dynamic>{};
        final rawCourseMastery = courseState['mastery'];
        final courseMastery = rawCourseMastery is Map ? rawCourseMastery : <dynamic, dynamic>{};
        final topics = <String>{'All', ...words.map((word) => word.topic)}.toList()..sort();
        final filtered = words.where((word) {
          final levelMatch = _level == 'All' || word.level == _level;
          final topicMatch = _topic == 'All' || word.topic == _topic;
          final query = _query.trim().toLowerCase();
          final queryMatch = query.isEmpty ||
              word.german.toLowerCase().contains(query) ||
              word.english.toLowerCase().contains(query) ||
              word.topic.toLowerCase().contains(query);
          return levelMatch && topicMatch && queryMatch;
        }).toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth < 500 ? 16.0 : 24.0;
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 28),
                children: [
                  Text('Vocabulary', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    '${words.length} words from the original A1–B1 vocabulary library, available offline.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      labelText: 'Search German or English',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'All', label: Text('All')),
                      ButtonSegment(value: 'A1', label: Text('A1')),
                      ButtonSegment(value: 'A2', label: Text('A2')),
                      ButtonSegment(value: 'B1', label: Text('B1')),
                    ],
                    selected: {_level},
                    onSelectionChanged: (value) => setState(() {
                      _level = value.first;
                      _topic = 'All';
                    }),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: topics.contains(_topic) ? _topic : 'All',
                    decoration: const InputDecoration(
                      labelText: 'Topic',
                      border: OutlineInputBorder(),
                    ),
                    items: topics
                        .map(
                          (topic) => DropdownMenuItem(
                            value: topic,
                            child: Text(topic, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _topic = value ?? 'All'),
                  ),
                  const SizedBox(height: 12),
                  Text('${filtered.length} matching words', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  ...filtered.map((word) {
                    // Native answer events use the namespaced ID; the legacy
                    // browser course uses v17-style keys for this same word.
                    final rawProgress = mastery['vocabulary:${word.number}'] ??
                        mastery['v${word.number}'] ??
                        courseMastery['v${word.number}'];
                    final progress = rawProgress is Map
                        ? Map<String, dynamic>.from(rawProgress)
                        : null;
                    return _WordCard(word: word, mastery: progress);
                  }),
                  if (filtered.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No vocabulary matches your filters.'),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, this.mastery});

  final VocabularyWord word;
  final Map<String, dynamic>? mastery;

  String? get _masteryLabel {
    final status = (mastery?['status'] ?? '').toString().toUpperCase();
    switch (status) {
      case 'MASTERED':
        return 'Mastered';
      case 'STRONG':
      case 'LEARNED':
        return 'Strong';
      case 'LEARNING':
        return 'Learning';
      case 'WEAK':
        return 'Needs practice';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(word.level, style: theme.textTheme.labelMedium),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(word.displayGerman, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(word.english, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 3),
                  Text(word.topic, style: theme.textTheme.bodySmall),
                  if (_masteryLabel != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(_masteryLabel!),
                          avatar: Icon(
                            _masteryLabel == 'Mastered' || _masteryLabel == 'Strong'
                                ? Icons.check_circle_outline
                                : Icons.auto_stories_outlined,
                            size: 17,
                          ),
                        ),
                        Text(
                          '${mastery?['correct'] ?? 0}/${mastery?['attempts'] ?? 0} correct',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text('Vocabulary could not be loaded.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
