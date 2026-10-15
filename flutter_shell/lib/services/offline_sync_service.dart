import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assignment_submission_service.dart';
import 'offline_assignment_progress_service.dart';
import 'offline_assignment_submission_queue_service.dart';
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
    required this.assignmentProgressCount,
    required this.pendingAssignmentProgressCount,
    required this.writtenSubmissionCount,
    required this.feedback,
  });

  final DateTime syncedAt;
  final int sessionCount;
  final int totalQuestions;
  final int correctAnswers;
  final int accuracyPercent;
  final int assignmentProgressCount;
  final int pendingAssignmentProgressCount;
  final int writtenSubmissionCount;
  final List<SyncFeedback> feedback;
}

class OfflineSyncService {
  OfflineSyncService(this._client, this.userId)
      : _progress = ProgressService(userId),
        _assignmentProgress = OfflineAssignmentProgressService(userId),
        _writtenSubmissions = OfflineAssignmentSubmissionQueueService(userId);

  final SupabaseClient _client;
  final String userId;
  final ProgressService _progress;
  final OfflineAssignmentProgressService _assignmentProgress;
  final OfflineAssignmentSubmissionQueueService _writtenSubmissions;

  String get _lastSyncKey => 'sprachtreppe_last_sync_v1_$userId';
  String get _pendingClientIdKey => 'sprachtreppe_pending_sync_id_v1_$userId';
  String get _lastSyncedClientIdKey => 'sprachtreppe_last_synced_client_id_v1_$userId';
  String get _lastSnapshotKey => 'sprachtreppe_last_snapshot_v1_$userId';

  static const weeklyInterval = Duration(days: 7);

  /// A stable representation of the local sessions and their derived totals.
  /// Keeping this in local preferences lets repeat syncs reuse their server id.
  static String sessionSnapshot(
    List<StudySession> sessions,
    ProgressStats stats, {
    Map<String, Map<String, Object>> assignments =
        const <String, Map<String, Object>>{},
    Map<String, Object> writtenSubmissions = const <String, Object>{},
  }) {
    final stableAssignments = <String, Object>{};
    final assignmentKeys = assignments.keys.toList()..sort();
    for (final key in assignmentKeys) {
      stableAssignments[key] = assignments[key]!;
    }
    final stableWrittenSubmissions = <String, Object>{};
    final writtenKeys = writtenSubmissions.keys.toList()..sort();
    for (final key in writtenKeys) {
      stableWrittenSubmissions[key] = writtenSubmissions[key]!;
    }
    return jsonEncode({
      'sessions': sessions.map((session) => session.toJson()).toList(),
      'assignments': stableAssignments,
      'written_submissions': stableWrittenSubmissions,
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
    final pendingAssignments = await _assignmentProgress.loadForSync();
    final pendingWrittenSubmissions = await _writtenSubmissions.loadAll();
    final now = DateTime.now().toUtc();

    Map<String, Object> writtenSnapshot(
      List<PendingWrittenSubmission> submissions,
    ) {
      final result = <String, Object>{};
      for (final submission in submissions) {
        result[submission.clientId] = submission.toSnapshotJson();
      }
      return result;
    }

    // Include queued written responses in the local snapshot so retries are stable
    // and new/edited answers are not mistaken for an unchanged successful sync.
    final snapshot = sessionSnapshot(
      sessions,
      stats,
      assignments: pendingAssignments,
      writtenSubmissions: writtenSnapshot(pendingWrittenSubmissions),
    );
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

    final feedback = <SyncFeedback>[];

    // Assignment progress must update assignment_progress, not only the generic
    // weekly submission snapshot. Keep failed items queued and continue syncing
    // general study history so one retired/unavailable task cannot lock the learner.
    final syncedAssignmentSnapshots = <String, Map<String, Object>>{};
    for (final entry in pendingAssignments.entries) {
      try {
        await _client.rpc(
          'update_assignment_progress',
          params: assignmentProgressRpcParams(entry.key, entry.value),
        );
        syncedAssignmentSnapshots[entry.key] = entry.value;
      } catch (_) {
        // The matching snapshot remains in local storage and will be retried later.
      }
    }

    // Send each queued written response with its own stable client ID. If one fails,
    // its queue record stays locally and the global sync timestamp is not advanced.
    for (final submission in pendingWrittenSubmissions) {
      final rawWritten = await _client.rpc(
        'submit_progress',
        params: {
          'p_payload': buildAssignmentResponsePayload(
            assignment: submission.assignment,
            response: submission.response,
            submittedAt: submission.submittedAt,
          ),
          'p_client_id': submission.clientId,
        },
      );
      if (rawWritten is! Map) {
        throw StateError('The server returned an unexpected written-submission response.');
      }
      final writtenResult = Map<String, dynamic>.from(rawWritten);
      if (writtenResult['ok'] != true || writtenResult['skipped'] == 'admin') {
        throw StateError('The server did not confirm a queued written response.');
      }
      _appendFeedback(writtenResult, feedback);
      try {
        await _writtenSubmissions.clearSynced(submission);
      } catch (_) {
        // Idempotent client IDs make retrying an uncleared local record safe.
      }
    }

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
      'assignments': pendingAssignments,
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
    _appendFeedback(response, feedback);

    // Clear only snapshots confirmed by the assignment RPC; newer or failed
    // entries remain locally queued for a later retry.
    try {
      await _assignmentProgress.clearSynced(syncedAssignmentSnapshots);
    } catch (_) {
      // Retain the local copy if cleanup fails; server-side upserts are monotonic.
    }

    var pendingAssignmentProgressCount = pendingAssignments.length;
    var snapshotAfterSync = snapshot;
    try {
      final remainingAssignments = await _assignmentProgress.loadForSync();
      pendingAssignmentProgressCount = remainingAssignments.length;
      final remainingWrittenSubmissions = await _writtenSubmissions.loadAll();
      snapshotAfterSync = sessionSnapshot(
        sessions,
        stats,
        assignments: remainingAssignments,
        writtenSubmissions: writtenSnapshot(remainingWrittenSubmissions),
      );
    } catch (_) {
      // Keep the existing stable snapshot if reading the local queue fails.
    }

    await preferences.setString(_lastSyncKey, syncedAt.toIso8601String());
    await preferences.setString(_lastSyncedClientIdKey, clientId);
    await preferences.setString(_lastSnapshotKey, snapshotAfterSync);
    await preferences.remove(_pendingClientIdKey);

    return OfflineSyncResult(
      syncedAt: syncedAt,
      sessionCount: stats.totalSessions,
      totalQuestions: stats.totalQuestions,
      correctAnswers: stats.correctAnswers,
      accuracyPercent: stats.accuracyPercent,
      assignmentProgressCount: syncedAssignmentSnapshots.length,
      pendingAssignmentProgressCount: pendingAssignmentProgressCount,
      writtenSubmissionCount: pendingWrittenSubmissions.length,
      feedback: {
        for (final item in feedback) item.id: item,
      }.values.toList(),
    );
  }

  /// Converts one locally queued cumulative counter snapshot into the canonical
  /// assignment RPC contract shared with the web client.
  static Map<String, dynamic> assignmentProgressRpcParams(
    String assignmentId,
    Map<String, Object> snapshot,
  ) {
    final id = int.tryParse(assignmentId);
    final done = _syncInt(snapshot['done']);
    final correct = _syncInt(snapshot['ok'] ?? snapshot['correct']);
    if (id == null || id < 1 || done < 0 || correct < 0 || correct > done) {
      throw const FormatException('Invalid queued assignment progress.');
    }
    return {
      'p_assignment': id,
      'p_done': done,
      'p_correct': correct,
    };
  }

  static int _syncInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  Future<void> acknowledgeFeedback(Iterable<int> ids) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return;
    await _client.rpc('ack_feedback', params: {'p_ids': uniqueIds});
  }
}


void _appendFeedback(
  Map<String, dynamic> response,
  List<SyncFeedback> destination,
) {
  final raw = response['feedback'];
  if (raw is! List) return;
  for (final row in raw.whereType<Map>()) {
    final item = Map<String, dynamic>.from(row);
    if (item['id'] is num) destination.add(SyncFeedback.fromJson(item));
  }
}
