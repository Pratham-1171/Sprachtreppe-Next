import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'progress_service.dart';

/// Pull/merge/push service for personal learning state shared by all devices.
/// Local events are persisted before network work; sync failure never clears offline records.
class LearningStateSyncService {
  LearningStateSyncService(this._client, this.userId, {ProgressService? progress})
      : _progress = progress ?? ProgressService(userId);

  final SupabaseClient _client;
  final String userId;
  final ProgressService _progress;

  static final Map<String, Timer> _syncTimers = <String, Timer>{};
  static final Random _random = Random();

  String get _eventsKey => 'sprachtreppe_learning_answer_events_v1_$userId';
  static const int maxLocalEvents = 5000;
  static const int maxEventsPerSync = 1000;

  /// Save an immutable answer event locally first, then debounce a background
  /// sync. Event IDs make retries idempotent across devices.
  Future<void> recordAnswer({
    required String mode,
    required String level,
    required String topic,
    required String prompt,
    required String answer,
    required String expected,
    required bool correct,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await _readEvents(prefs);
    final micros = DateTime.now().microsecondsSinceEpoch;
    final event = <String, Object>{
      'id': 'answer-' + micros.toString() + '-' + _random.nextInt(1 << 32).toRadixString(16),
      'type': 'answer',
      'entityType': mode.toLowerCase().contains('grammar') ? 'grammar' : 'vocabulary',
      'entityId': _normaliseKey('$mode|$level|$topic|$prompt'),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'mode': mode,
      'level': level,
      'topic': topic.length > 120 ? topic.substring(0, 120) : topic,
      'prompt': prompt.length > 320 ? prompt.substring(0, 320) : prompt,
      'answer': answer.length > 180 ? answer.substring(0, 180) : answer,
      'expected': expected.length > 180 ? expected.substring(0, 180) : expected,
      'correct': correct,
    };
    events.add(event);
    final saved = _deduplicateEvents(events)..sort(_compareEvents);
    await prefs.setString(_eventsKey, jsonEncode(saved.length > maxLocalEvents
        ? saved.sublist(saved.length - maxLocalEvents)
        : saved));
    _scheduleSync();
  }

  /// Merge remote events and sessions; push the merged view back so counters
  /// derived from two offline devices become consistent rather than overwritten.
  Future<void> sync() async {
    final user = _client.auth.currentUser;
    if (user == null || user.id != userId) {
      throw StateError('Sign in again before synchronizing your learning progress.');
    }
    final prefs = await SharedPreferences.getInstance();
    var localEvents = mergeEvents(null, await _readEvents(prefs));
    var localSessions = await _progress.loadSessions();

    // Multiple passes absorb concurrent writes which arrive while devices sync.
    for (var pass = 0; pass < 3; pass++) {
      final payload = <String, Object>{
        'flutter': _buildFlutterState(localSessions, localEvents),
      };
      final raw = await _client.rpc('sync_learning_state', params: {'p_state': payload});
      if (raw is! Map) throw StateError('The learning-state server returned an invalid response.');
      final response = Map<String, dynamic>.from(raw);
      final rawState = response['state'];
      if (rawState is! Map) throw StateError('The learning-state response has no state object.');
      final fullState = Map<String, dynamic>.from(rawState);
      final rawFlutter = fullState['flutter'];
      final cloudFlutter = rawFlutter is Map
          ? Map<String, dynamic>.from(rawFlutter)
          : <String, dynamic>{};

      localEvents = mergeEvents(cloudFlutter['answerEvents'], localEvents);
      localSessions = await _progress.mergeSessions(_readSessionsFromState(cloudFlutter['sessions']));
      await prefs.setString(_eventsKey, jsonEncode(localEvents));
    }
  }

  void _scheduleSync() {
    _syncTimers.remove(userId)?.cancel();
    _syncTimers[userId] = Timer(const Duration(seconds: 3), () {
      _syncTimers.remove(userId);
      sync().catchError((Object _) {
        // Keep the queue on device; launch/resume/manual sync retries it.
      });
    });
  }

  Future<List<Map<String, dynamic>>> _readEvents(SharedPreferences prefs) async {
    final encoded = prefs.getString(_eventsKey);
    if (encoded == null || encoded.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return _deduplicateEvents(decoded.whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      ).toList());
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static List<Map<String, dynamic>> mergeEvents(dynamic remote, List<Map<String, dynamic>> local) {
    final incoming = <Map<String, dynamic>>[];
    if (remote is List) {
      incoming.addAll(remote.whereType<Map>().map((item) => Map<String, dynamic>.from(item)));
    }
    incoming.addAll(local);
    final merged = _deduplicateEvents(incoming)..sort(_compareEvents);
    return merged.length > maxEventsPerSync
        ? merged.sublist(merged.length - maxEventsPerSync)
        : merged;
  }

  static List<Map<String, dynamic>> _deduplicateEvents(List<Map<String, dynamic>> events) {
    final byId = <String, Map<String, dynamic>>{};
    for (final event in events) {
      final id = event['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final existing = byId[id];
      if (existing == null) {
        byId[id] = event;
      } else {
        final oldTime = DateTime.tryParse(existing['timestamp']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final newTime = DateTime.tryParse(event['timestamp']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        if (newTime.isAfter(oldTime)) byId[id] = event;
      }
    }
    return byId.values.toList();
  }

  static int _compareEvents(Map<String, dynamic> a, Map<String, dynamic> b) {
    final at = DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final bt = DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return at.compareTo(bt);
  }

  static List<StudySession> _readSessionsFromState(dynamic value) {
    if (value is! List) return <StudySession>[];
    final sessions = <StudySession>[];
    for (final item in value.whereType<Map>()) {
      try {
        sessions.add(StudySession.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // Skip one malformed record and keep other study records.
      }
    }
    return sessions;
  }

  static String _normaliseKey(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length > 300 ? normalized.substring(0, 300) : normalized;
  }

  static Map<String, Object> _buildFlutterState(
    List<StudySession> sessions,
    List<Map<String, dynamic>> events,
  ) {
    final stats = ProgressStats.fromSessions(sessions);
    final vocab = <String, Map<String, Object>>{};
    final grammar = <String, Map<String, Object>>{};
    final mistakes = <String, Map<String, Object>>{};
    for (final event in events) {
      final id = event['entityId']?.toString() ?? 'unknown';
      final type = event['entityType']?.toString() ?? 'vocabulary';
      final item = type == 'grammar'
          ? grammar.putIfAbsent(id, () => <String, Object>{'attempts': 0, 'correct': 0, 'completed': false})
          : vocab.putIfAbsent(id, () => <String, Object>{'attempts': 0, 'correct': 0, 'status': 'NEW'});
      item['attempts'] = (item['attempts'] as int) + 1;
      if (event['correct'] == true) item['correct'] = (item['correct'] as int) + 1;
      if (type == 'grammar') {
        item['completed'] = true;
      } else {
        final attempts = item['attempts'] as int;
        final correct = item['correct'] as int;
        final rate = correct / attempts;
        item['status'] = attempts >= 3 && rate >= 0.85
            ? 'MASTERED'
            : rate >= 0.6
                ? 'STRONG'
                : event['correct'] == true
                    ? 'LEARNING'
                    : 'WEAK';
      }
      if (event['correct'] != true) {
        final mistake = mistakes.putIfAbsent(id, () => <String, Object>{'count': 0, 'topic': event['topic']?.toString() ?? ''});
        mistake['count'] = (mistake['count'] as int) + 1;
      }
    }

    return <String, Object>{
      'schemaVersion': 1,
      'sessions': sessions.map((session) => session.toJson()).toList(),
      'answerEvents': events,
      'vocabularyMastery': vocab,
      'grammarCompletion': grammar,
      'mistakes': mistakes,
      'summary': <String, Object>{
        'totalSessions': stats.totalSessions,
        'totalQuestions': stats.totalQuestions,
        'correctAnswers': stats.correctAnswers,
        'accuracyPercent': stats.accuracyPercent,
        'currentStreak': stats.currentStreak,
        'bestStreak': stats.bestStreak,
        'sessionsToday': stats.sessionsToday,
      },
    };
  }
}
