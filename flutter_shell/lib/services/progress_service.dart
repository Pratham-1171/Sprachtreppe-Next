import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StudySession {
  const StudySession({
    required this.completedAt,
    required this.mode,
    required this.level,
    required this.correct,
    required this.total,
  });

  final DateTime completedAt;
  final String mode;
  final String level;
  final int correct;
  final int total;

  Map<String, Object> toJson() => {
        'completedAt': completedAt.toIso8601String(),
        'mode': mode,
        'level': level,
        'correct': correct,
        'total': total,
      };

  factory StudySession.fromJson(Map<String, dynamic> json) {
    return StudySession(
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      mode: json['mode'] as String? ?? 'Practice',
      level: json['level'] as String? ?? 'All',
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
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
    final preferences = await _resolvePreferences();
    final sessions = await _readSessions(preferences);
    sessions.insert(
      0,
      StudySession(
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
