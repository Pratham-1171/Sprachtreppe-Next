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
  static final Map<String, Future<void>> _queueTails = <String, Future<void>>{};
  static final Map<String, Future<void>> _syncFlights = <String, Future<void>>{};
  static final Random _random = Random();

  String get _eventsKey => 'sprachtreppe_learning_answer_events_v1_$userId';
  String get _recentEventsKey => 'sprachtreppe_learning_recent_answer_events_v1_$userId';
  String get _aggregateKey => 'sprachtreppe_learning_aggregates_v1_$userId';
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
    String? entityId,
  }) async {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final event = <String, Object>{
      'id': 'answer-$micros-${_random.nextInt(1 << 32).toRadixString(16)}',
      'type': 'answer',
      'entityType': mode.toLowerCase().contains('grammar') ? 'grammar' : 'vocabulary',
      'entityId': _normaliseKey(entityId ?? '$mode|$level|$topic|$prompt'),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'mode': mode,
      'level': level,
      'topic': topic.length > 80 ? topic.substring(0, 80) : topic,
      'prompt': prompt.length > 180 ? prompt.substring(0, 180) : prompt,
      'answer': answer.length > 120 ? answer.substring(0, 120) : answer,
      'expected': expected.length > 120 ? expected.substring(0, 120) : expected,
      'correct': correct,
    };
    await _withQueueLock(() async {
      final prefs = await SharedPreferences.getInstance();
      final pending = await _readEvents(prefs);
      pending.add(event);
      final saved = _deduplicateEvents(pending)..sort(_compareEvents);
      // Do not evict old offline answers to stay under an arbitrary event cap.
      // A storage failure must be visible to the caller rather than discarding
      // previously queued work.
      final persisted = await prefs.setString(_eventsKey, jsonEncode(saved));
      if (!persisted) throw StateError('Could not persist the offline answer queue.');
    });
    _scheduleSync();
  }

  /// Merge remote events and sessions; push the merged view back so counters
  /// derived from two offline devices become consistent rather than overwritten.
  Future<void> sync() {
    final ongoing = _syncFlights[userId];
    if (ongoing != null) return ongoing;
    final task = _performSync();
    _syncFlights[userId] = task;
    return task.whenComplete(() {
      if (identical(_syncFlights[userId], task)) _syncFlights.remove(userId);
    });
  }

  Future<void> _performSync() async {
    final user = _client.auth.currentUser;
    if (user == null || user.id != userId) {
      throw StateError('Sign in again before synchronizing your learning progress.');
    }
    final prefs = await SharedPreferences.getInstance();
    // This key contains only unconfirmed offline work; do not truncate it to one batch.
    final pendingEvents = _deduplicateEvents(await _readEvents(prefs))..sort(_compareEvents);
    final localSessions = await _progress.loadSessions();

    for (final batch in batchEvents(pendingEvents)) {
      final upload = await _client.rpc(
        'sync_learning_answer_events',
        params: {'p_events': batch},
      );
      // The server returns accepted_ids, including IDs it had already seen.
      // A successful RPC is also safe to acknowledge on older compatible servers
      // because inserts are unique by (student_id, event_id).
      final response = upload is Map
          ? Map<String, dynamic>.from(upload)
          : <String, dynamic>{};
      final rawAccepted = response['accepted_ids'];
      final acknowledged = rawAccepted is List
          ? rawAccepted.map((id) => id.toString()).toSet()
          : batch.map((event) => event['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty).toSet();
      await _acknowledgeEvents(prefs, acknowledged);
    }

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

    // The durable event ledger is returned separately from the compact state
    // document; don't depend on the latest-500 event window to acknowledge work.
    final rawServerEvents = response['answer_events'];
    await _progress.mergeSessions(<StudySession>[
      ..._readSessionsFromState(cloudFlutter['sessions']),
      ...readWebSessionsFromState(fullState['sessionHistory']),
    ]);

    // Serialize local cache writes with recordAnswer(). Previously acknowledged
    // batches were removed by ID immediately after their RPC succeeded; any new
    // answers created while this sync was in flight remain queued untouched.
    await _withQueueLock(() async {
      final currentPending = await _readEvents(prefs);
      final recentServerEvents = mergeEvents(rawServerEvents, currentPending);
      final savedRecent = await prefs.setString(_recentEventsKey, jsonEncode(recentServerEvents));
      if (!savedRecent) throw StateError('Could not cache the latest synced answer history.');
      final rawCourseState = fullState;
      await prefs.setString(_aggregateKey, jsonEncode(<String, Object>{
        'vocabularyMastery': cloudFlutter['vocabularyMastery'] is Map
            ? cloudFlutter['vocabularyMastery'] : <String, Object>{},
        'grammarCompletion': cloudFlutter['grammarCompletion'] is Map
            ? cloudFlutter['grammarCompletion'] : <String, Object>{},
        'mistakes': cloudFlutter['mistakes'] is Map
            ? cloudFlutter['mistakes'] : <String, Object>{},
        'summary': cloudFlutter['summary'] is Map
            ? cloudFlutter['summary'] : <String, Object>{},
        // Preserve the actual legacy-course state too. Flutter cannot execute the
        // browser engine, but it can display/consume the exact remote mastery,
        // completion, streak, activity and achievement state without dropping it.
        'courseState': <String, Object>{
          'known': rawCourseState['known'] is Map ? rawCourseState['known'] as Map : <String, Object>{},
          'mastery': rawCourseState['mastery'] is Map ? rawCourseState['mastery'] as Map : <String, Object>{},
          'bookmarked': rawCourseState['bookmarked'] is Map ? rawCourseState['bookmarked'] as Map : <String, Object>{},
          'grammarDone': rawCourseState['grammarDone'] is Map ? rawCourseState['grammarDone'] as Map : <String, Object>{},
          'quizStats': rawCourseState['quizStats'] is Map ? rawCourseState['quizStats'] as Map : <String, Object>{},
          'gstats': rawCourseState['gstats'] is Map ? rawCourseState['gstats'] as Map : <String, Object>{},
          'mistakes': rawCourseState['mistakes'] is Map ? rawCourseState['mistakes'] as Map : <String, Object>{},
          'streak': rawCourseState['streak'] is Map ? rawCourseState['streak'] as Map : <String, Object>{},
          'studyTime': rawCourseState['studyTime'] is Map ? rawCourseState['studyTime'] as Map : <String, Object>{},
          'practiceActivity': rawCourseState['practiceActivity'] is Map ? rawCourseState['practiceActivity'] as Map : <String, Object>{},
          'achievements': rawCourseState['achievements'] is Map ? rawCourseState['achievements'] as Map : <String, Object>{},
          'settings': rawCourseState['settings'] is Map ? rawCourseState['settings'] as Map : <String, Object>{},
          'sessionHistory': rawCourseState['sessionHistory'] is List ? rawCourseState['sessionHistory'] as List : <Object>[],
        },
        'revision': response['revision'] is num ? response['revision'] : 0,
        'updatedAt': response['updated_at']?.toString() ?? '',
      }));
    });
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
        if (_client.auth.currentUser?.id == userId) _scheduleRetry();
      });
    });
  }

  void _scheduleRetry() {
    _syncTimers.remove(userId)?.cancel();
    _syncTimers[userId] = Timer(const Duration(seconds: 30), () {
      _syncTimers.remove(userId);
      if (_client.auth.currentUser?.id != userId) return;
      sync().catchError((Object _) {
        if (_client.auth.currentUser?.id == userId) _scheduleRetry();
      });
    });
  }

  Future<void> _acknowledgeEvents(
    SharedPreferences prefs,
    Set<String> acknowledgedIds,
  ) async {
    if (acknowledgedIds.isEmpty) return;
    await _withQueueLock(() async {
      final current = await _readEvents(prefs);
      final remaining = withoutAcknowledgedEvents(current, acknowledgedIds);
      final persisted = await prefs.setString(_eventsKey, jsonEncode(remaining));
      if (!persisted) {
        // Keep the original queue if local storage refuses the update. Retrying
        // the same IDs later is harmless because the database has a unique key.
        throw StateError('Could not acknowledge synced answers in local storage.');
      }
    });
  }

  /// Pure ID-based acknowledgement: only server-confirmed events are removed.
  /// New events added while a request is in flight remain in the returned queue.
  static List<Map<String, dynamic>> withoutAcknowledgedEvents(
    List<Map<String, dynamic>> events,
    Set<String> acknowledgedIds,
  ) {
    final remaining = events.where(
      (event) => !acknowledgedIds.contains(event['id']?.toString() ?? ''),
    ).toList();
    return _deduplicateEvents(remaining)..sort(_compareEvents);
  }

  Future<T> _withQueueLock<T>(Future<T> Function() operation) async {
    final previous = _queueTails[userId] ?? Future<void>.value();
    final completer = Completer<void>();
    final ownTail = completer.future;
    _queueTails[userId] = ownTail;
    await previous;
    try {
      return await operation();
    } finally {
      completer.complete();
      if (identical(_queueTails[userId], ownTail)) _queueTails.remove(userId);
    }
  }

  Future<List<Map<String, dynamic>>> _readEvents(SharedPreferences prefs) async {
    final encoded = prefs.getString(_eventsKey);
    if (encoded == null || encoded.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        throw StateError('Saved offline answer queue is not a list; it was not cleared.');
      }
      return _deduplicateEvents(decoded.whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      ).toList());
    } on StateError {
      rethrow;
    } catch (_) {
      // Never interpret an unreadable offline queue as empty and overwrite it.
      throw StateError('Saved offline answer queue is unreadable; it was not cleared.');
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

  /// Imports browser-course sessions into native history, using stable IDs.
  static List<StudySession> readWebSessionsFromState(dynamic value) {
    if (value is! List) return <StudySession>[];
    final sessions = <StudySession>[];
    for (final item in value.whereType<Map>()) {
      try {
        final row = Map<String, dynamic>.from(item);
        final dateValue = row['date']?.toString() ?? '';
        final questionsValue = row['questions'];
        final correctValue = row['correct'];
        final questions = questionsValue is num
            ? questionsValue.toInt()
            : int.tryParse(questionsValue?.toString() ?? '') ?? 0;
        final correct = correctValue is num
            ? correctValue.toInt()
            : int.tryParse(correctValue?.toString() ?? '') ?? 0;
        if (dateValue.isEmpty || questions <= 0) continue;
        final parsed = DateTime.tryParse(dateValue);
        if (parsed == null) continue;
        final rawId = row['id']?.toString();
        if (rawId == null || rawId.isEmpty) continue;
        // Browser history prefixes native IDs for the course's own session list.
        // Strip that alias when re-importing so native and browser views of the
        // exact same session do not count it twice.
        final stableId = rawId.startsWith('flutter-session:')
            ? rawId.substring('flutter-session:'.length)
            : rawId;
        sessions.add(StudySession(
          id: stableId,
          completedAt: parsed,
          mode: row['mode']?.toString() ?? 'Web course',
          level: row['level']?.toString() ?? 'All',
          correct: correct.clamp(0, questions).toInt(),
          total: questions,
        ));
      } catch (_) {
        // Skip one malformed session while keeping the remaining history.
      }
    }
    return sessions;
  }

  static String _normaliseKey(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length > 160 ? normalized.substring(0, 160) : normalized;
  }

  /// Recent answer history imported from another device, available offline.
  Future<List<Map<String, dynamic>>> loadRecentEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_recentEventsKey);
    if (encoded == null || encoded.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((event) => Map<String, dynamic>.from(event)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// Read the downloaded materialized mastery and mistakes even while offline.
  Future<Map<String, dynamic>> loadAggregateState() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_aggregateKey);
    if (encoded == null || encoded.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }


}
