import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'progress_service.dart';

class SyncFeedback {
  const SyncFeedback({
    required this.id,
    required this.status,
    required this.note,
    required this.rating,
    required this.reviewedAt,
  });

  final int id;
  final String status;
  final String? note;
  final int? rating;
  final DateTime? reviewedAt;

  factory SyncFeedback.fromJson(Map<String, dynamic> json) => SyncFeedback(
        id: (json['id'] as num).toInt(),
        status: json['status'] as String? ?? 'reviewed',
        note: json['note'] as String?,
        rating: json['rating'] is num ? (json['rating'] as num).toInt() : null,
        reviewedAt: DateTime.tryParse(json['reviewed_at']?.toString() ?? ''),
      );
}

class OfflineSyncResult {
  const OfflineSyncResult({
    required this.syncedAt,
    required this.sessionCount,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.accuracyPercent,
    required this.feedback,
  });

  final DateTime syncedAt;
  final int sessionCount;
  final int totalQuestions;
  final int correctAnswers;
  final int accuracyPercent;
  final List<SyncFeedback> feedback;
}

class OfflineSyncService {
  OfflineSyncService(this._client, this.userId)
      : _progress = ProgressService(userId);

  final SupabaseClient _client;
  final String userId;
  final ProgressService _progress;

  String get _lastSyncKey => 'sprachtreppe_last_sync_v1_$userId';
  String get _pendingClientIdKey => 'sprachtreppe_pending_sync_id_v1_$userId';
  String get _lastSyncedClientIdKey => 'sprachtreppe_last_synced_client_id_v1_$userId';
  String get _lastSnapshotKey => 'sprachtreppe_last_snapshot_v1_$userId';

  static const weeklyInterval = Duration(days: 7);

  /// A stable representation of the local sessions and their derived totals.
  /// Keeping this in local preferences lets repeat syncs reuse their server id.
  static String sessionSnapshot(List<StudySession> sessions, ProgressStats stats) {
    return jsonEncode({
      'sessions': sessions.map((session) => session.toJson()).toList(),
      'summary': {
        'session_count': stats.totalSessions,
        'total_questions': stats.totalQuestions,
        'correct_answers': stats.correctAnswers,
        'accuracy_percent': stats.accuracyPercent,
        'current_streak': stats.currentStreak,
        'best_streak': stats.bestStreak,
      },
    });
  }

  static bool isSyncDue(DateTime? lastSyncAt, {DateTime? now}) {
    if (lastSyncAt == null) return true;
    final current = (now ?? DateTime.now()).toLocal();
    return current.difference(lastSyncAt.toLocal()) >= weeklyInterval;
  }

  Future<DateTime?> loadLastSyncAt() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_lastSyncKey);
    return encoded == null ? null : DateTime.tryParse(encoded);
  }

  Future<OfflineSyncResult> syncNow() async {
    final user = _client.auth.currentUser;
    if (user == null || user.id != userId) {
      throw StateError('Please sign in again before syncing progress.');
    }

    final preferences = await SharedPreferences.getInstance();
    final sessions = await _progress.loadSessions();
    final stats = ProgressStats.fromSessions(sessions);
    final now = DateTime.now().toUtc();

    // Reuse a pending id after network failure. If the saved snapshot is unchanged,
    // also reuse its successful id so a manual repeat does not create a duplicate review.
    final snapshot = sessionSnapshot(sessions, stats);
    final pendingClientId = preferences.getString(_pendingClientIdKey);
    final previousClientId = preferences.getString(_lastSyncedClientIdKey);
    final unchangedSnapshot =
        snapshot == preferences.getString(_lastSnapshotKey) && previousClientId != null;
    final clientId = pendingClientId ??
        (unchangedSnapshot ? previousClientId : 'flutter-${now.microsecondsSinceEpoch}');
    if (clientId.length < 8 || clientId.length > 64) {
      throw StateError('The local sync identifier is invalid. Clear app storage only if this persists.');
    }
    await preferences.setString(_pendingClientIdKey, clientId);

    final payload = <String, Object>{
      'summary': <String, Object>{
        'source': 'flutter_offline_progress_sync',
        'synced_at': now.toIso8601String(),
        'session_count': stats.totalSessions,
        'total_questions': stats.totalQuestions,
        'correct_answers': stats.correctAnswers,
        'accuracy_percent': stats.accuracyPercent,
        'current_streak': stats.currentStreak,
        'best_streak': stats.bestStreak,
      },
      'practice_sessions': sessions.map((session) => session.toJson()).toList(),
    };

    final raw = await _client.rpc(
      'submit_progress',
      params: {'p_payload': payload, 'p_client_id': clientId},
    );
    if (raw is! Map) {
      throw StateError('The server returned an unexpected sync response.');
    }
    final response = Map<String, dynamic>.from(raw);
    if (response['ok'] != true) {
      throw StateError('The server did not confirm the progress sync.');
    }
    if (response['skipped'] == 'admin') {
      throw StateError('Progress sync is available for student accounts only.');
    }

    final syncedAt = DateTime.tryParse(response['server_time']?.toString() ?? '') ?? now;
    final feedback = <SyncFeedback>[];
    final rawFeedback = response['feedback'];
    if (rawFeedback is List) {
      for (final row in rawFeedback.whereType<Map>()) {
        final item = Map<String, dynamic>.from(row);
        if (item['id'] is num) feedback.add(SyncFeedback.fromJson(item));
      }
    }

    await preferences.setString(_lastSyncKey, syncedAt.toIso8601String());
    await preferences.setString(_lastSyncedClientIdKey, clientId);
    await preferences.setString(_lastSnapshotKey, snapshot);
    await preferences.remove(_pendingClientIdKey);

    return OfflineSyncResult(
      syncedAt: syncedAt,
      sessionCount: stats.totalSessions,
      totalQuestions: stats.totalQuestions,
      correctAnswers: stats.correctAnswers,
      accuracyPercent: stats.accuracyPercent,
      feedback: feedback,
    );
  }

  Future<void> acknowledgeFeedback(Iterable<int> ids) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return;
    await _client.rpc('ack_feedback', params: {'p_ids': uniqueIds});
  }
}
