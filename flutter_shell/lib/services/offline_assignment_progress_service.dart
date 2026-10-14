import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingAssignmentProgress {
  const PendingAssignmentProgress({
    required this.assignmentId,
    required this.done,
    required this.correct,
  });

  final int assignmentId;
  final int done;
  final int correct;

  Map<String, Object> toStorageJson() => {
        'done': done,
        'correct': correct,
      };

  Map<String, Object> toSyncJson() => {
        'done': done,
        'ok': correct,
      };

  factory PendingAssignmentProgress.fromJson(
    int assignmentId,
    Map<String, dynamic> json,
  ) {
    final rawDone = _assignmentInt(json['done']);
    final done = rawDone < 0 ? 0 : rawDone;
    final rawCorrect = _assignmentInt(json['correct'] ?? json['ok']);
    final correct = rawCorrect.clamp(0, done).toInt();
    return PendingAssignmentProgress(
      assignmentId: assignmentId,
      done: done,
      correct: correct,
    );
  }
}

/// Persists assignment progress while the assignment RPC is unavailable.
class OfflineAssignmentProgressService {
  OfflineAssignmentProgressService(
    this.userId, {
    SharedPreferences? preferences,
  }) : _preferences = preferences;

  final String userId;
  final SharedPreferences? _preferences;

  String get _storageKey => 'sprachtreppe_pending_assignment_progress_v1_$userId';

  Future<SharedPreferences> _resolvePreferences() async {
    final cached = _preferences;
    if (cached != null) return cached;
    return SharedPreferences.getInstance();
  }

  Future<Map<int, PendingAssignmentProgress>> loadAll() async {
    final preferences = await _resolvePreferences();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return {};

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        await preferences.remove(_storageKey);
        return {};
      }

      final result = <int, PendingAssignmentProgress>{};
      for (final entry in decoded.entries) {
        final assignmentId = int.tryParse(entry.key.toString());
        if (assignmentId == null || assignmentId < 1 || entry.value is! Map) continue;
        result[assignmentId] = PendingAssignmentProgress.fromJson(
          assignmentId,
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
      return result;
    } catch (_) {
      await preferences.remove(_storageKey);
      return {};
    }
  }

  Future<PendingAssignmentProgress?> loadOne(int assignmentId) async {
    return (await loadAll())[assignmentId];
  }

  Future<PendingAssignmentProgress> recordProgress({
    required int assignmentId,
    required int done,
    required int correct,
  }) async {
    if (assignmentId < 1 || done < 0 || correct < 0 || correct > done) {
      throw ArgumentError('Invalid assignment progress values.');
    }

    final pending = await loadAll();
    final previous = pending[assignmentId];
    final mergedDone = previous == null
        ? done
        : (previous.done > done ? previous.done : done);
    final mergedCorrect = previous == null
        ? correct
        : (previous.correct > correct ? previous.correct : correct);
    final saved = PendingAssignmentProgress(
      assignmentId: assignmentId,
      done: mergedDone,
      correct: mergedCorrect.clamp(0, mergedDone).toInt(),
    );
    pending[assignmentId] = saved;
    await _save(pending);
    return saved;
  }

  /// Converts pending items to the shape consumed by submit_progress.
  Future<Map<String, Map<String, Object>>> loadForSync() async {
    final pending = await loadAll();
    final ids = pending.keys.toList()..sort();
    final payload = <String, Map<String, Object>>{};
    for (final id in ids) {
      payload[id.toString()] = pending[id]!.toSyncJson();
    }
    return payload;
  }

  /// Removes only entries that still match the snapshot sent to the server.
  /// Newer learner progress remains queued.
  Future<void> clearSynced(
    Map<String, Map<String, Object>> sent,
  ) async {
    if (sent.isEmpty) return;
    final pending = await loadAll();
    var changed = false;

    for (final entry in sent.entries) {
      final id = int.tryParse(entry.key);
      if (id == null) continue;
      final current = pending[id];
      final sentDone = _assignmentInt(entry.value['done']);
      final sentCorrect = _assignmentInt(entry.value['ok']);
      if (current != null &&
          current.done == sentDone &&
          current.correct == sentCorrect) {
        pending.remove(id);
        changed = true;
      }
    }

    if (changed) await _save(pending);
  }

  Future<void> _save(Map<int, PendingAssignmentProgress> pending) async {
    final preferences = await _resolvePreferences();
    if (pending.isEmpty) {
      await preferences.remove(_storageKey);
      return;
    }

    final ids = pending.keys.toList()..sort();
    final encoded = <String, Object>{};
    for (final id in ids) {
      encoded[id.toString()] = pending[id]!.toStorageJson();
    }
    await preferences.setString(_storageKey, jsonEncode(encoded));
  }
}

int _assignmentInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
