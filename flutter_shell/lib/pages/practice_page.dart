import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/grammar_lesson.dart';
import '../models/vocabulary_word.dart';
import '../services/grammar_service.dart';
import '../services/learning_state_sync_service.dart';
import '../services/offline_assignment_progress_service.dart';
import '../services/progress_service.dart';
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
  const PracticePage({
    super.key,
    required this.userId,
    this.assignmentId,
    this.assignmentTitle,
    this.assignmentTargetCount,
    this.assignmentDone = 0,
    this.assignmentCorrect = 0,
    this.assignmentSkill,
  });

  final String userId;
  final int? assignmentId;
  final String? assignmentTitle;
  final int? assignmentTargetCount;
  final int assignmentDone;
  final int assignmentCorrect;
  final String? assignmentSkill;

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
  bool _savingProgress = false;
  bool _progressSaveFailed = false;
  bool _assignmentSyncFailed = false;
  String? _assignmentNotice;
  int? _pendingAssignmentDone;
  int? _pendingAssignmentCorrect;
  late int _assignmentDoneNow;
  late int _assignmentCorrectNow;
  late final OfflineAssignmentProgressService _assignmentProgress;

  List<_PracticeMode> get _availableModes {
    if (widget.assignmentId == null) return _PracticeMode.values;
    final skill = widget.assignmentSkill?.toLowerCase() ?? '';
    if (skill.contains('grammar')) return const [_PracticeMode.grammar];
    if (skill.contains('article')) return const [_PracticeMode.articles];
    if (skill.contains('vocab') || skill.contains('word')) {
      return const [_PracticeMode.germanToEnglish, _PracticeMode.englishToGerman];
    }
    return _PracticeMode.values;
  }

  _PracticeMode _modeForSkill(String? skillValue) {
    final skill = skillValue?.toLowerCase() ?? '';
    if (skill.contains('article')) return _PracticeMode.articles;
    if (skill.contains('vocab') || skill.contains('word') || skill == 'de-en') {
      return _PracticeMode.germanToEnglish;
    }
    return _PracticeMode.grammar;
  }

  String? get _progressNotice {
    final notices = <String>[];
    if (_progressSaveFailed) {
      notices.add('The round finished, but local progress could not be saved.');
    }
    if (_assignmentNotice != null) notices.add(_assignmentNotice!);
    return notices.isEmpty ? null : notices.join('\n');
  }

  @override
  void initState() {
    super.initState();
    _assignmentDoneNow = widget.assignmentDone;
    _assignmentCorrectNow = widget.assignmentCorrect;
    _assignmentProgress = OfflineAssignmentProgressService(widget.userId);
    if (widget.assignmentId != null) {
      _mode = _modeForSkill(widget.assignmentSkill);
      _restorePendingAssignmentProgress().then((_) {
        if (mounted) _loadLibrary();
      });
    } else {
      _loadLibrary();
    }
  }

  Future<void> _restorePendingAssignmentProgress() async {
    final assignmentId = widget.assignmentId;
    if (assignmentId == null) return;
    try {
      final pending = await _assignmentProgress.loadOne(assignmentId);
      if (pending == null) return;
      _assignmentDoneNow = math.max(_assignmentDoneNow, pending.done);
      _assignmentCorrectNow = math.max(_assignmentCorrectNow, pending.correct);
    } catch (_) {
      // Local queue restoration is best-effort and must not block practice.
    }
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
    _savingProgress = false;
    _progressSaveFailed = false;
    _assignmentSyncFailed = false;
    _assignmentNotice = null;
    _pendingAssignmentDone = null;
    _pendingAssignmentCorrect = null;
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
    final remaining = widget.assignmentId == null
        ? 10
        : math.max(0, (widget.assignmentTargetCount ?? 10) - _assignmentDoneNow);
    return pool.take(math.min(math.min(10, remaining), pool.length)).toList();
  }

  void _selectAnswer(int index) {
    if (_selectedIndex != null || _questions.isEmpty) return;
    final question = _questions[_questionIndex];
    final isCorrect = index == question.correctIndex;
    setState(() {
      _selectedIndex = index;
      if (isCorrect) _score++;
    });
    // Persist the answer locally, including wrong answers, before relying on network sync.
    LearningStateSyncService(Supabase.instance.client, widget.userId).recordAnswer(
      mode: _mode.label,
      level: _level,
      topic: question.detail,
      prompt: question.prompt,
      answer: question.options[index],
      expected: question.options[question.correctIndex],
      correct: isCorrect,
    ).catchError((Object _) {});
  }

  Future<void> _nextQuestion() async {
    if (_questionIndex < _questions.length - 1) {
      setState(() {
        _questionIndex++;
        _selectedIndex = null;
      });
      return;
    }

    setState(() => _savingProgress = true);
    var saveFailed = false;
    try {
      await ProgressService(widget.userId).recordSession(
        mode: _mode.label,
        level: _level,
        correct: _score,
        total: _questions.length,
      );
    } catch (_) {
      saveFailed = true;
    }

    int? pendingDone;
    int? pendingCorrect;
    var assignmentSyncFailed = false;
    String? assignmentNotice;
    if (widget.assignmentId != null && widget.assignmentTargetCount != null) {
      final doneForSync = math.min(
        widget.assignmentTargetCount!,
        _assignmentDoneNow + _questions.length,
      );
      final correctForSync = math.min(doneForSync, _assignmentCorrectNow + _score);
      pendingDone = doneForSync;
      pendingCorrect = correctForSync;
      var savedLocally = false;
      try {
        await _assignmentProgress.recordProgress(
          assignmentId: widget.assignmentId!,
          done: doneForSync,
          correct: correctForSync,
        );
        savedLocally = true;
      } catch (_) {
        // Still attempt the online update. A successful server write is enough.
      }

      try {
        await _writeAssignmentProgress(doneForSync, correctForSync);
        if (savedLocally) {
          try {
            await _assignmentProgress.clearSynced({
              widget.assignmentId!.toString(): {
                'done': doneForSync,
                'ok': correctForSync,
              },
            });
          } catch (_) {
            // A later sync can clear this harmless local copy.
          }
        }
        assignmentNotice = doneForSync >= widget.assignmentTargetCount!
            ? 'Assignment completed and reported to your account.'
            : 'Assignment progress saved to your account.';
      } catch (_) {
        assignmentSyncFailed = true;
        assignmentNotice = savedLocally
            ? 'Assignment progress is saved on this device and will sync when you reconnect.'
            : 'Could not sync or save assignment progress locally. Reconnect and retry.';
      }
    }

    if (!mounted) return;
    setState(() {
      _finished = true;
      _savingProgress = false;
      _progressSaveFailed = saveFailed;
      _assignmentSyncFailed = assignmentSyncFailed;
      _pendingAssignmentDone = pendingDone;
      _pendingAssignmentCorrect = pendingCorrect;
      _assignmentNotice = assignmentNotice;
      if (!assignmentSyncFailed && pendingDone != null && pendingCorrect != null) {
        _assignmentDoneNow = pendingDone;
        _assignmentCorrectNow = pendingCorrect;
      }
    });
  }

  Future<void> _writeAssignmentProgress(int done, int correct) async {
    final assignmentId = widget.assignmentId;
    if (assignmentId == null) return;
    await Supabase.instance.client.rpc(
      'update_assignment_progress',
      params: {
        'p_assignment': assignmentId,
        'p_done': done,
        'p_correct': correct,
      },
    );
  }

  Future<void> _retryAssignmentSync() async {
    final done = _pendingAssignmentDone;
    final correct = _pendingAssignmentCorrect;
    if (!_assignmentSyncFailed || done == null || correct == null) return;
    setState(() => _savingProgress = true);
    try {
      await _writeAssignmentProgress(done, correct);
      try {
        await _assignmentProgress.clearSynced({
          widget.assignmentId!.toString(): {
            'done': done,
            'ok': correct,
          },
        });
      } catch (_) {
        // Keep the queue for weekly sync if local cleanup fails.
      }
      if (!mounted) return;
      setState(() {
        _savingProgress = false;
        _assignmentSyncFailed = false;
        _assignmentDoneNow = done;
        _assignmentCorrectNow = correct;
        _assignmentNotice = done >= (widget.assignmentTargetCount ?? done)
            ? 'Assignment completed and reported to your account.'
            : 'Assignment progress saved to your account.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingProgress = false;
        _assignmentNotice = 'Still unable to sync. Check the connection and retry.';
      });
    }
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
        Text(widget.assignmentTitle ?? 'Practice', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          widget.assignmentId == null
              ? 'Short offline rounds to strengthen grammar and vocabulary.'
              : 'Complete the questions below. Progress is saved locally and synced to your account when connected.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Text('Choose practice', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in _availableModes)
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
            progressNotice: _progressNotice,
            retryLoading: _savingProgress,
            onRetryAssignment: _assignmentSyncFailed ? _retryAssignmentSync : null,
            restartLabel: widget.assignmentId != null &&
                    !_assignmentSyncFailed &&
                    _assignmentDoneNow >= (widget.assignmentTargetCount ?? 0)
                ? 'Return to assignment'
                : 'Start a new round',
            onRestart: () {
              if (widget.assignmentId != null &&
                  !_assignmentSyncFailed &&
                  _assignmentDoneNow >= (widget.assignmentTargetCount ?? 0)) {
                Navigator.of(context).pop();
              } else {
                setState(() => _resetRound(library));
              }
            },
          )
        else
          _buildQuestionCard(theme),
        const SizedBox(height: 12),
        Text(
          'Practice runs offline. Study history and unsynced assignment progress are stored on this device for the weekly sync.',
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
                onPressed: _savingProgress ? null : _nextQuestion,
                child: _savingProgress
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_questionIndex == _questions.length - 1
                        ? 'Save round & see results'
                        : 'Next question'),
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
    this.progressNotice,
    this.onRetryAssignment,
    this.retryLoading = false,
    this.restartLabel = 'Start a new round',
  });

  final int score;
  final int total;
  final VoidCallback onRestart;
  final String? progressNotice;
  final VoidCallback? onRetryAssignment;
  final bool retryLoading;
  final String restartLabel;

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
            if (progressNotice != null) ...[
              const SizedBox(height: 8),
              Text(progressNotice!, textAlign: TextAlign.center),
            ],
            if (onRetryAssignment != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: retryLoading ? null : onRetryAssignment,
                  icon: retryLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Retry assignment sync'),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRetryAssignment != null ? null : onRestart,
                icon: const Icon(Icons.refresh),
                label: Text(restartLabel),
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
