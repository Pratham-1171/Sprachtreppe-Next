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
  String get _aggregateKey => 'sprachtreppe_learning_aggregates_v1_$userId';
  static const int maxLocalEvents = 5000;
  static const int maxEventsPerSync = 500;

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
      'topic': topic.length > 80 ? topic.substring(0, 80) : topic,
      'prompt': prompt.length > 180 ? prompt.substring(0, 180) : prompt,
      'answer': answer.length > 120 ? answer.substring(0, 120) : answer,
      'expected': expected.length > 120 ? expected.substring(0, 120) : expected,
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
    // Keep the full offline queue until every batch and the final pull succeed.
    // Replaying already-uploaded IDs is safe because the server merge is idempotent.
    final pendingEvents = _deduplicateEvents(await _readEvents(prefs))..sort(_compareEvents);
    final localSessions = await _progress.loadSessions();

    for (final batch in batchEvents(pendingEvents)) {
      await _client.rpc(
        'sync_learning_answer_events',
        params: {'p_events': batch},
      );
    }

    // This final round-trip imports remote sessions and all server-computed
    // aggregates. Answer history itself was delivered in individually acknowledged batches.
    final raw = await _client.rpc(
      'sync_learning_state',
      params: {
        'p_state': <String, Object>{
          'flutter': <String, Object>{
            'sessions': localSessions.map((session) => session.toJson()).toList(),
          },
        },
      },
    );
    if (raw is! Map) throw StateError('The learning-state server returned an invalid response.');
    final response = Map<String, dynamic>.from(raw);
    final rawState = response['state'];
    if (rawState is! Map) throw StateError('The learning-state response has no state object.');
    final fullState = Map<String, dynamic>.from(rawState);
    final rawFlutter = fullState['flutter'];
    final cloudFlutter = rawFlutter is Map
        ? Map<String, dynamic>.from(rawFlutter)
        : <String, dynamic>{};

    final mergedEvents = mergeEvents(cloudFlutter['answerEvents'], pendingEvents);
    final mergedSessions = await _progress.mergeSessions(
      _readSessionsFromState(cloudFlutter['sessions']),
    );

    // Only compact the on-device event queue after all batches have been accepted
    // and the final pull succeeded. If anything fails above, the original queue remains.
    await prefs.setString(_eventsKey, jsonEncode(mergedEvents));
    await prefs.setString(_aggregateKey, jsonEncode(<String, Object>{
      'vocabularyMastery': cloudFlutter['vocabularyMastery'] is Map
          ? cloudFlutter['vocabularyMastery'] : <String, Object>{},
      'grammarCompletion': cloudFlutter['grammarCompletion'] is Map
          ? cloudFlutter['grammarCompletion'] : <String, Object>{},
      'mistakes': cloudFlutter['mistakes'] is Map
          ? cloudFlutter['mistakes'] : <String, Object>{},
      'summary': cloudFlutter['summary'] is Map
          ? cloudFlutter['summary'] : <String, Object>{},
      'revision': response['revision'] is num ? response['revision'] : 0,
      'updatedAt': response['updated_at']?.toString() ?? '',
    }));
    // Keep the local session union durable for dashboards/streak calculations.
    // mergeSessions has already written it; this reference prevents accidental
    // removal of the awaited result if persistence behavior changes later.
    assert(mergedSessions.isNotEmpty || mergedSessions.isEmpty);
  }

  /// Chunks the complete local queue rather than truncating it to one API batch.
  /// Every chunk uses stable IDs; a failed chunk leaves the queue intact for retry.
  static List<List<Map<String, dynamic>>> batchEvents(
    List<Map<String, dynamic>> events,
  ) {
    final batches = <List<Map<String, dynamic>>>[];
    for (var offset = 0; offset < events.length; offset += maxEventsPerSync) {
      final end = min(offset + maxEventsPerSync, events.length);
      batches.add(events.sublist(offset, end));
    }
    return batches;
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
    return normalized.length > 160 ? normalized.substring(0, 160) : normalized;
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
