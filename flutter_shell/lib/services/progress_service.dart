import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StudySession {
  const StudySession({
    required this.completedAt,
    required this.mode,
    required this.level,
    required this.correct,
    required this.total,
    this.id = '',
  });

  final String id;
  final DateTime completedAt;
  final String mode;
  final String level;
  final int correct;
  final int total;

  String get stableId => id.isNotEmpty
      ? id
      : 'legacy:${completedAt.toUtc().toIso8601String()}:${mode.toLowerCase()}:$level:$correct:$total';

  Map<String, Object> toJson() => {
        'id': stableId,
        'completedAt': completedAt.toIso8601String(),
        'mode': mode,
        'level': level,
        'correct': correct,
        'total': total,
      };

  factory StudySession.fromJson(Map<String, dynamic> json) {
    final completedAt = DateTime.tryParse(json['completedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final mode = json['mode'] as String? ?? 'Practice';
    final level = json['level'] as String? ?? 'All';
    final correct = (json['correct'] as num?)?.toInt() ?? 0;
    final total = (json['total'] as num?)?.toInt() ?? 0;
    return StudySession(
      id: (json['id'] as String?) ??
          'legacy:${completedAt.toUtc().toIso8601String()}:${mode.toLowerCase()}:$level:$correct:$total',
      completedAt: completedAt,
      mode: mode,
      level: level,
      correct: correct,
      total: total,
    );
  }
}

class ProgressStats {
  const ProgressStats({
    required this.totalSessions,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.accuracyPercent,
    required this.currentStreak,
    required this.bestStreak,
    required this.sessionsToday,
    required this.lastStudiedAt,
  });

  final int totalSessions;
  final int totalQuestions;
  final int correctAnswers;
  final int accuracyPercent;
  final int currentStreak;
  final int bestStreak;
  final int sessionsToday;
  final DateTime? lastStudiedAt;

  factory ProgressStats.fromSessions(
    List<StudySession> sessions, {
    DateTime? now,
  }) {
    final valid = sessions.where((session) => session.total > 0).toList();
    final totalQuestions = valid.fold<int>(0, (sum, session) => sum + session.total);
    final correctAnswers = valid.fold<int>(
      0,
      (sum, session) => sum + session.correct.clamp(0, session.total).toInt(),
    );
    final accuracy = totalQuestions == 0
        ? 0
        : (correctAnswers * 100 / totalQuestions).round();

    final currentTime = (now ?? DateTime.now()).toLocal();
    final today = DateTime.utc(currentTime.year, currentTime.month, currentTime.day);
    final studyDays = valid.map((session) {
      final local = session.completedAt.toLocal();
      return DateTime.utc(local.year, local.month, local.day);
    }).toSet().toList()
      ..sort();

    final daySet = studyDays.toSet();
    var currentStreak = 0;
    DateTime? cursor;
    if (daySet.contains(today)) {
      cursor = today;
    } else {
      final yesterday = today.subtract(const Duration(days: 1));
      if (daySet.contains(yesterday)) cursor = yesterday;
    }
    while (cursor != null && daySet.contains(cursor)) {
      currentStreak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    var bestStreak = 0;
    var runLength = 0;
    DateTime? previousDay;
    for (final day in studyDays) {
      if (previousDay != null && day.difference(previousDay) == const Duration(days: 1)) {
        runLength++;
      } else {
        runLength = 1;
      }
      if (runLength > bestStreak) bestStreak = runLength;
      previousDay = day;
    }

    final sessionsToday = valid.where((session) {
      final date = session.completedAt.toLocal();
      return date.year == currentTime.year &&
          date.month == currentTime.month &&
          date.day == currentTime.day;
    }).length;

    DateTime? lastStudiedAt;
    for (final session in valid) {
      final completedAt = session.completedAt.toLocal();
      if (lastStudiedAt == null || completedAt.isAfter(lastStudiedAt)) {
        lastStudiedAt = completedAt;
      }
    }

    return ProgressStats(
      totalSessions: valid.length,
      totalQuestions: totalQuestions,
      correctAnswers: correctAnswers,
      accuracyPercent: accuracy,
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      sessionsToday: sessionsToday,
      lastStudiedAt: lastStudiedAt,
    );
  }
}

class ProgressService {
  static final Map<String, Future<void>> _sessionTails = <String, Future<void>>{};

  ProgressService(this.userId, {SharedPreferences? preferences})
      : _preferences = preferences;

  final String userId;
  final SharedPreferences? _preferences;

  String get _storageKey => 'sprachtreppe_progress_v1_$userId';

  Future<SharedPreferences> _resolvePreferences() async {
    final cached = _preferences;
    if (cached != null) return cached;
    return SharedPreferences.getInstance();
  }

  Future<List<StudySession>> loadSessions() async {
    final preferences = await _resolvePreferences();
    return _readSessions(preferences);
  }

  Future<ProgressStats> loadStats({DateTime? now}) async {
    return ProgressStats.fromSessions(await loadSessions(), now: now);
  }

  Future<ProgressStats> recordSession({
    required String mode,
    required String level,
    required int correct,
    required int total,
    DateTime? completedAt,
  }) async {
    if (total <= 0) return loadStats();
    return _withSessionLock(() async {
      final preferences = await _resolvePreferences();
      final sessions = await _readSessions(preferences);
      sessions.insert(
        0,
        StudySession(
          id: 'session-${DateTime.now().microsecondsSinceEpoch}',
          completedAt: completedAt ?? DateTime.now(),
          mode: mode,
          level: level,
          correct: correct.clamp(0, total).toInt(),
          total: total,
        ),
      );

      const historyLimit = 500;
      final saved = sessions.take(historyLimit).map((session) {
        return jsonEncode(session.toJson());
      }).toList();
      await preferences.setStringList(_storageKey, saved);
      return ProgressStats.fromSessions(sessions);
    });
  }

  /// Merge imported sessions with local offline sessions by their stable event ID.
  /// A session synced by two devices is persisted only once.
  Future<List<StudySession>> mergeSessions(Iterable<StudySession> incoming) async {
    return _withSessionLock(() async {
      final preferences = await _resolvePreferences();
      final all = <String, StudySession>{};
      for (final session in await _readSessions(preferences)) {
        all[session.stableId] = session;
      }
      for (final session in incoming) {
        all.putIfAbsent(session.stableId, () => session);
      }
      final merged = all.values.toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
      final saved = merged.take(500).toList();
      await preferences.setStringList(
        _storageKey,
        saved.map((session) => jsonEncode(session.toJson())).toList(),
      );
      return saved;
    });
  }

  Future<T> _withSessionLock<T>(Future<T> Function() operation) async {
    final previous = _sessionTails[userId] ?? Future<void>.value();
    final completer = Completer<void>();
    final ownTail = completer.future;
    _sessionTails[userId] = ownTail;
    await previous;
    try {
      return await operation();
    } finally {
      completer.complete();
      if (identical(_sessionTails[userId], ownTail)) _sessionTails.remove(userId);
    }
  }

  Future<List<StudySession>> _readSessions(
    SharedPreferences preferences,
  ) async {
    final encoded = preferences.getStringList(_storageKey) ?? const <String>[];
    final sessions = <StudySession>[];
    for (final item in encoded) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          sessions.add(StudySession.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Ignore one corrupted local record instead of losing the whole history.
      }
    }
    return sessions;
  }
}
