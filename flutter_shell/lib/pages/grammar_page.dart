import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/grammar_lesson.dart';
import '../services/grammar_service.dart';
import '../services/learning_state_sync_service.dart';
import '../services/progress_service.dart';

class GrammarPage extends StatefulWidget {
  const GrammarPage({super.key, required this.userId});

  final String userId;

  @override
  State<GrammarPage> createState() => _GrammarPageState();
}

class _GrammarPageState extends State<GrammarPage> {
  final _service = const GrammarService();
  late Future<List<GrammarSection>> _future;
  String _level = 'All';
  String _query = '';
  Map<String, dynamic> _learningState = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _future = _service.loadSections();
    _loadSharedProgress();
  }

  Future<void> _loadSharedProgress() async {
    final sync = LearningStateSyncService(Supabase.instance.client, widget.userId);
    try {
      await sync.sync();
    } catch (_) {
      // Cached state stays visible offline; queued answer events are retained.
    }
    final state = await sync.loadAggregateState();
    if (mounted) setState(() => _learningState = state);
  }

  String _lessonKey(GrammarLesson lesson) => 'grammar:${lesson.level}:${lesson.title}';

  bool _isCompleted(GrammarLesson lesson) {
    final raw = _learningState['grammarCompletion'];
    final progress = raw is Map ? raw[_lessonKey(lesson)] : null;
    if (progress is Map && (progress['completed'] == true || progress['completed'] == 'true')) {
      return true;
    }
    final rawCourse = _learningState['courseState'];
    final course = rawCourse is Map ? rawCourse : <dynamic, dynamic>{};
    final done = course['grammarDone'];
    if (done is Map) {
      return done[lesson.title] == true || done['${lesson.level}:${lesson.title}'] == true;
    }
    return false;
  }

  void _recordLocalResult(GrammarLesson lesson, bool correct) {
    final key = _lessonKey(lesson);
    final grammarRaw = _learningState['grammarCompletion'];
    final grammar = grammarRaw is Map
        ? Map<String, dynamic>.from(grammarRaw)
        : <String, dynamic>{};
    final oldRaw = grammar[key];
    final old = oldRaw is Map ? Map<String, dynamic>.from(oldRaw) : <String, dynamic>{};
    final previousAttempts = old['attempts'] is num ? (old['attempts'] as num).toInt() : 0;
    final previousCorrect = old['correct'] is num ? (old['correct'] as num).toInt() : 0;
    grammar[key] = <String, Object>{
      ...old,
      'attempted': true,
      'completed': old['completed'] == true || correct,
      'attempts': previousAttempts + 1,
      'correct': previousCorrect + (correct ? 1 : 0),
    };

    final next = Map<String, dynamic>.from(_learningState);
    next['grammarCompletion'] = grammar;
    if (!correct) {
      final mistakesRaw = _learningState['mistakes'];
      final mistakes = mistakesRaw is Map
          ? Map<String, dynamic>.from(mistakesRaw)
          : <String, dynamic>{};
      final oldMistakeRaw = mistakes[key];
      final oldMistake = oldMistakeRaw is Map
          ? Map<String, dynamic>.from(oldMistakeRaw)
          : <String, dynamic>{};
      final oldCount = oldMistake['count'] is num
          ? (oldMistake['count'] as num).toInt()
          : 0;
      mistakes[key] = <String, Object>{
        ...oldMistake,
        'count': oldCount + 1,
        'topic': lesson.title,
      };
      next['mistakes'] = mistakes;
    }
    setState(() => _learningState = next);
  }

  Future<void> _reload() async {
    setState(() => _future = _service.loadSections());
    await _future;
    await _loadSharedProgress();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GrammarSection>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _LoadError(onRetry: _reload);

        final sections = snapshot.data ?? const <GrammarSection>[];
        final allLessons = sections.expand((section) => section.lessons).toList();
        final query = _query.trim().toLowerCase();
        final visibleSections = sections
            .where((section) => _level == 'All' || section.level == _level)
            .map((section) {
              final lessons = section.lessons.where((lesson) {
                if (query.isEmpty) return true;
                final searchText = [
                  lesson.title,
                  lesson.explanation,
                  lesson.rule,
                  lesson.guide.when,
                  lesson.guide.tip,
                  ...lesson.examples.expand((pair) => pair),
                ].join(' ').toLowerCase();
                return searchText.contains(query);
              }).toList();
              return _VisibleSection(section: section, lessons: lessons);
            })
            .where((section) => section.lessons.isNotEmpty)
            .toList();
        final visibleCount = visibleSections.fold<int>(
          0,
          (total, section) => total + section.lessons.length,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth < 500 ? 16.0 : 24.0;
            final theme = Theme.of(context);
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 28),
                children: [
                  Text('Grammar', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    '${allLessons.length} A1–B1 lessons with simple rules, examples, mistakes to avoid, and quick checks. Works offline.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      labelText: 'Search a grammar topic',
                      hintText: 'e.g. weil, Dativ, word order',
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
                    onSelectionChanged: (value) => setState(() => _level = value.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$visibleCount of ${allLessons.length} lessons',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      if (_level != 'All' || query.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _level = 'All';
                            _query = '';
                          }),
                          icon: const Icon(Icons.clear, size: 18),
                          label: const Text('Clear filters'),
                        ),
                    ],
                  ),
                  if (visibleSections.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Column(
                        children: [
                          Icon(Icons.search_off, size: 40),
                          SizedBox(height: 8),
                          Text('No grammar topics match your search.'),
                        ],
                      ),
                    ),
                  for (final visible in visibleSections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                      child: Text(
                        '${visible.section.level} · ${visible.section.title}',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    for (final lesson in visible.lessons)
                      _GrammarLessonTile(
                        key: PageStorageKey<String>('${lesson.level}-${lesson.title}'),
                        lesson: lesson,
                        userId: widget.userId,
                        isCompleted: _isCompleted(lesson),
                        onAnswered: (correct) => _recordLocalResult(lesson, correct),
                      ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _VisibleSection {
  const _VisibleSection({required this.section, required this.lessons});

  final GrammarSection section;
  final List<GrammarLesson> lessons;
}

class _GrammarLessonTile extends StatelessWidget {
  const _GrammarLessonTile({
    super.key,
    required this.lesson,
    required this.userId,
    required this.isCompleted,
    required this.onAnswered,
  });

  final GrammarLesson lesson;
  final String userId;
  final bool isCompleted;
  final ValueChanged<bool> onAnswered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        leading: CircleAvatar(
          radius: 20,
          child: Text(lesson.level, style: theme.textTheme.labelSmall),
        ),
        title: Text(
          lesson.title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(isCompleted ? '✓ Completed · ${lesson.explanation}' : lesson.explanation),
        children: [
          if (lesson.guide.when.isNotEmpty)
            _InfoBlock(
              icon: Icons.lightbulb_outline,
              title: 'When to use it',
              child: Text(lesson.guide.when),
            ),
          if (lesson.guide.steps.isNotEmpty)
            _InfoBlock(
              icon: Icons.format_list_numbered,
              title: 'How to build it',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < lesson.guide.steps.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${index + 1}. ', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Expanded(child: Text(lesson.guide.steps[index])),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          _InfoBlock(
            icon: Icons.rule,
            title: 'Rule / pattern',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                lesson.rule,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (lesson.examples.isNotEmpty)
            _InfoBlock(
              icon: Icons.chat_bubble_outline,
              title: 'Examples',
              child: Column(
                children: [
                  for (final pair in lesson.examples)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pair[0], style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(pair[1], style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (lesson.mistakes.isNotEmpty)
            _InfoBlock(
              icon: Icons.spellcheck,
              title: 'Common mistakes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final pair in lesson.mistakes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pair[0], style: TextStyle(color: theme.colorScheme.error)),
                          const SizedBox(height: 3),
                          Text(pair[1], style: TextStyle(color: theme.colorScheme.primary)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (lesson.guide.contrast.isNotEmpty)
            _InfoBlock(
              icon: Icons.compare_arrows,
              title: 'Remember the difference',
              child: Text(lesson.guide.contrast),
            ),
          if (lesson.guide.tip.isNotEmpty)
            _InfoBlock(
              icon: Icons.tips_and_updates_outlined,
              title: 'Memory tip',
              child: Text(lesson.guide.tip),
            ),
          if (lesson.exercise != null)
            _InteractiveExercise(
              key: ValueKey<String>('${lesson.level}-${lesson.title}-exercise'),
              userId: userId,
              lesson: lesson,
              exercise: lesson.exercise!,
              onAnswered: onAnswered,
            ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _InteractiveExercise extends StatefulWidget {
  const _InteractiveExercise({
    super.key,
    required this.userId,
    required this.lesson,
    required this.exercise,
    required this.onAnswered,
  });

  final String userId;
  final GrammarLesson lesson;
  final GrammarExercise exercise;
  final ValueChanged<bool> onAnswered;

  @override
  State<_InteractiveExercise> createState() => _InteractiveExerciseState();
}

class _InteractiveExerciseState extends State<_InteractiveExercise> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercise = widget.exercise;
    final answered = _selectedIndex != null;
    final isCorrect = _selectedIndex == exercise.correctIndex;

    return _InfoBlock(
      icon: Icons.quiz_outlined,
      title: 'Quick practice',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(exercise.question, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          for (var index = 0; index < exercise.options.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: answered
                    ? null
                    : () {
                        final correct = index == exercise.correctIndex;
                        setState(() => _selectedIndex = index);
                        widget.onAnswered(correct);
                        LearningStateSyncService(
                          Supabase.instance.client,
                          widget.userId,
                        ).recordAnswer(
                          mode: 'Grammar',
                          level: widget.lesson.level,
                          topic: widget.lesson.title,
                          prompt: exercise.question,
                          answer: exercise.options[index],
                          expected: exercise.options[exercise.correctIndex],
                          correct: correct,
                          entityId: 'grammar:${widget.lesson.level}:${widget.lesson.title}',
                        ).catchError((Object _) {});
                        ProgressService(widget.userId).recordSession(
                          mode: 'Grammar quick check',
                          level: widget.lesson.level,
                          correct: correct ? 1 : 0,
                          total: 1,
                        ).then<void>((_) {}).catchError((Object _) {});
                      },
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  child: Text(
                    exercise.options[index],
                    softWrap: true,
                    textAlign: TextAlign.start,
                  ),
                ),
              ),
            ),
          if (answered) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isCorrect ? theme.colorScheme.primary : theme.colorScheme.error)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCorrect ? 'Correct!' : 'Not quite — review the answer.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isCorrect ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${exercise.options[exercise.correctIndex]} — ${exercise.explanation}',
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _selectedIndex = null),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 42),
            const SizedBox(height: 12),
            Text('Grammar could not be loaded', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('The offline lesson file may be missing. Please try again.'),
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
