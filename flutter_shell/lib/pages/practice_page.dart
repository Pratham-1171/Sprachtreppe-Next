import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/grammar_lesson.dart';
import '../models/vocabulary_word.dart';
import '../services/grammar_service.dart';
import '../services/vocabulary_service.dart';

enum _PracticeMode { grammar, germanToEnglish, englishToGerman, articles }

extension on _PracticeMode {
  String get label => switch (this) {
        _PracticeMode.grammar => 'Grammar',
        _PracticeMode.germanToEnglish => 'German → English',
        _PracticeMode.englishToGerman => 'English → German',
        _PracticeMode.articles => 'Articles',
      };
}

class PracticePage extends StatefulWidget {
  const PracticePage({super.key});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final _random = math.Random();
  bool _loading = true;
  Object? _loadError;
  _PracticeLibrary? _library;
  _PracticeMode _mode = _PracticeMode.grammar;
  String _level = 'All';
  List<_PracticeQuestion> _questions = const [];
  int _questionIndex = 0;
  int _score = 0;
  int? _selectedIndex;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    if (_library != null || _loadError != null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final results = await Future.wait<Object>([
        const GrammarService().loadSections(),
        const VocabularyService().loadWords(),
      ]);
      final library = _PracticeLibrary(
        sections: results[0] as List<GrammarSection>,
        words: results[1] as List<VocabularyWord>,
      );
      if (!mounted) return;
      setState(() {
        _library = library;
        _loading = false;
        _loadError = null;
        _resetRound(library);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _resetRound(_PracticeLibrary library) {
    _questions = _buildQuestions(library, _mode, _level);
    _questionIndex = 0;
    _score = 0;
    _selectedIndex = null;
    _finished = false;
  }

  void _changeMode(_PracticeMode mode) {
    final library = _library;
    if (library == null) return;
    setState(() {
      _mode = mode;
      _resetRound(library);
    });
  }

  void _changeLevel(String level) {
    final library = _library;
    if (library == null) return;
    setState(() {
      _level = level;
      _resetRound(library);
    });
  }

  List<_PracticeQuestion> _buildQuestions(
    _PracticeLibrary library,
    _PracticeMode mode,
    String level,
  ) {
    final pool = <_PracticeQuestion>[];

    if (mode == _PracticeMode.grammar) {
      for (final section in library.sections) {
        if (level != 'All' && section.level != level) continue;
        for (final lesson in section.lessons) {
          final exercise = lesson.exercise;
          if (exercise == null || exercise.options.length < 2) continue;
          pool.add(
            _PracticeQuestion(
              prompt: '${lesson.title}\n${exercise.question}',
              options: exercise.options,
              correctIndex: exercise.correctIndex,
              explanation: '${lesson.title}: ${exercise.explanation}',
              detail: '${lesson.level} grammar',
            ),
          );
        }
      }
    } else {
      var words = library.words.where((word) =>
          (level == 'All' || word.level == level) &&
          word.german.trim().isNotEmpty &&
          word.english.trim().isNotEmpty);
      if (mode == _PracticeMode.articles) {
        words = words.where((word) => const ['der', 'die', 'das'].contains(word.article));
      }
      final eligible = words.toList()..shuffle(_random);
      final sample = eligible.take(80).toList();

      final answerPool = <String>{};
      for (final word in eligible) {
        final answer = switch (mode) {
          _PracticeMode.germanToEnglish => word.english.trim(),
          _PracticeMode.englishToGerman => word.displayGerman.trim(),
          _PracticeMode.articles => word.article.trim(),
          _PracticeMode.grammar => '',
        };
        if (answer.isNotEmpty) answerPool.add(answer);
      }
      final allAnswers = answerPool.toList();

      for (final word in sample) {
        if (mode == _PracticeMode.articles) {
          const options = ['der', 'die', 'das'];
          pool.add(
            _PracticeQuestion(
              prompt: 'Which article belongs with “${word.german}”?',
              options: options,
              correctIndex: options.indexOf(word.article),
              explanation: 'Learn the noun together with its article: ${word.displayGerman}.',
              detail: word.topic,
            ),
          );
          continue;
        }

        final correct = mode == _PracticeMode.germanToEnglish
            ? word.english.trim()
            : word.displayGerman.trim();
        final distractors = allAnswers.where((answer) => answer != correct).toList()
          ..shuffle(_random);
        if (distractors.length < 3) continue;
        final options = <String>[correct, ...distractors.take(3)]..shuffle(_random);
        pool.add(
          _PracticeQuestion(
            prompt: mode == _PracticeMode.germanToEnglish
                ? 'What does “${word.displayGerman}” mean?'
                : 'Choose the German word for “${word.english}”.',
            options: options,
            correctIndex: options.indexOf(correct),
            explanation: '${word.displayGerman} = ${word.english}',
            detail: word.topic,
          ),
        );
      }
    }

    pool.shuffle(_random);
    return pool.take(math.min(10, pool.length)).toList();
  }

  void _selectAnswer(int index) {
    if (_selectedIndex != null || _questions.isEmpty) return;
    setState(() {
      _selectedIndex = index;
      if (index == _questions[_questionIndex].correctIndex) _score++;
    });
  }

  void _nextQuestion() {
    setState(() {
      if (_questionIndex >= _questions.length - 1) {
        _finished = true;
      } else {
        _questionIndex++;
        _selectedIndex = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) return _LoadError(onRetry: _loadLibrary);
    final library = _library;
    if (library == null) return _LoadError(onRetry: _loadLibrary);

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('Practice', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Short offline rounds to strengthen grammar and vocabulary.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Text('Choose practice', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in _PracticeMode.values)
              ChoiceChip(
                label: Text(mode.label),
                selected: _mode == mode,
                onSelected: (_) => _changeMode(mode),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'All', label: Text('All')),
            ButtonSegment(value: 'A1', label: Text('A1')),
            ButtonSegment(value: 'A2', label: Text('A2')),
            ButtonSegment(value: 'B1', label: Text('B1')),
          ],
          selected: {_level},
          onSelectionChanged: (value) => _changeLevel(value.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 16),
        if (_questions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.inbox_outlined, size: 40),
                  const SizedBox(height: 10),
                  Text('No questions available', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('Try another level or practice type.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _resetFromButton,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          )
        else if (_finished)
          _RoundSummary(
            score: _score,
            total: _questions.length,
            onRestart: () {
              setState(() => _resetRound(library));
            },
          )
        else
          _buildQuestionCard(theme),
        const SizedBox(height: 12),
        Text(
          'Practice runs offline. Scores are kept for this round; syncing study progress will be added in the progress stage.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  void _resetFromButton() {
    final library = _library;
    if (library == null) return;
    setState(() => _resetRound(library));
  }

  Widget _buildQuestionCard(ThemeData theme) {
    final question = _questions[_questionIndex];
    final answered = _selectedIndex != null;
    final correct = _selectedIndex == question.correctIndex;
    final progress = (_questionIndex + 1) / _questions.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Question ${_questionIndex + 1} of ${_questions.length}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Text('Score: $_score', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress, minHeight: 6),
            const SizedBox(height: 8),
            Text(question.detail, style: theme.textTheme.labelMedium),
            const SizedBox(height: 12),
            Text(
              question.prompt,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            for (var index = 0; index < question.options.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: answered ? null : () => _selectAnswer(index),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      side: BorderSide(
                        color: answered && index == question.correctIndex
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(question.options[index], softWrap: true),
                  ),
                ),
              ),
            if (answered) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (correct ? theme.colorScheme.primary : theme.colorScheme.error)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      correct ? 'Correct!' : 'Not quite',
                      style: TextStyle(
                        color: correct ? theme.colorScheme.primary : theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(question.explanation),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _nextQuestion,
                child: Text(_questionIndex == _questions.length - 1 ? 'See results' : 'Next question'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PracticeLibrary {
  const _PracticeLibrary({required this.sections, required this.words});

  final List<GrammarSection> sections;
  final List<VocabularyWord> words;
}

class _PracticeQuestion {
  const _PracticeQuestion({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.detail,
  });

  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String detail;
}

class _RoundSummary extends StatelessWidget {
  const _RoundSummary({
    required this.score,
    required this.total,
    required this.onRestart,
  });

  final int score;
  final int total;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = total == 0 ? 0 : (score * 100 / total).round();
    final message = percentage >= 80
        ? 'Great work — keep it up!'
        : percentage >= 50
            ? 'Good progress. Review the missed answers and try again.'
            : 'Keep practising. Repeating short rounds helps.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(
              percentage >= 80 ? Icons.emoji_events_outlined : Icons.school_outlined,
              size: 52,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('Round complete', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '$score / $total',
              style: theme.textTheme.headlineLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text('$percentage% correct', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.refresh),
                label: const Text('Start a new round'),
              ),
            ),
          ],
        ),
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
            const Icon(Icons.quiz_outlined, size: 42),
            const SizedBox(height: 12),
            Text('Practice data could not be loaded', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('Check the bundled lesson files and retry.'),
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
