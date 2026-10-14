import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/student_assignment.dart';
import 'assignment_submission_service.dart';

class PendingWrittenSubmission {
  const PendingWrittenSubmission({
    required this.assignmentId,
    required this.title,
    required this.kind,
    required this.skill,
    required this.targetCount,
    required this.correct,
    required this.response,
    required this.clientId,
    required this.submittedAt,
  });

  final int assignmentId;
  final String title;
  final String kind;
  final String skill;
  final int targetCount;
  final int correct;
  final String response;
  final String clientId;
  final DateTime submittedAt;

  StudentAssignment get assignment => StudentAssignment(
        id: assignmentId,
        className: null,
        title: title,
        instructions: '',
        kind: kind,
        skill: skill,
        targetCount: targetCount,
        dueAt: null,
        done: 0,
        correct: correct.clamp(0, targetCount).toInt(),
      );

  Map<String, dynamic> toPayload() => buildAssignmentResponsePayload(
        assignment: assignment,
        response: response,
        submittedAt: submittedAt,
      );

  Map<String, Object> toStorageJson() => {
        'assignment_id': assignmentId,
        'title': title,
        'kind': kind,
        'skill': skill,
        'target_count': targetCount,
        'correct': correct,
        'response': response,
        'client_id': clientId,
        'submitted_at': submittedAt.toUtc().toIso8601String(),
      };

  Map<String, Object> toSnapshotJson() => {
        'assignment_id': assignmentId,
        'title': title,
        'kind': kind,
        'skill': skill,
        'response': response,
        'client_id': clientId,
        'submitted_at': submittedAt.toUtc().toIso8601String(),
      };

  factory PendingWrittenSubmission.fromJson(Map<String, dynamic> json) {
    final assignmentId = _queueInt(json['assignment_id']);
    final rawTarget = _queueInt(json['target_count'], fallback: 1);
    final targetCount = rawTarget < 1 ? 1 : rawTarget;
    final rawCorrect = _queueInt(json['correct']);
    final response = (json['response'] as String? ?? '').trim();
    final clientId = (json['client_id'] as String? ?? '').trim();
    if (assignmentId < 1 ||
        response.isEmpty ||
        response.length > 5000 ||
        clientId.length < 8 ||
        clientId.length > 64) {
      throw const FormatException('Invalid queued assignment response.');
    }
    return PendingWrittenSubmission(
      assignmentId: assignmentId,
      title: json['title'] as String? ?? 'Assignment',
      kind: json['kind'] as String? ?? 'writing',
      skill: json['skill'] as String? ?? 'writing',
      targetCount: targetCount,
      correct: rawCorrect.clamp(0, targetCount).toInt(),
      response: response,
      clientId: clientId,
      submittedAt: DateTime.tryParse(json['submitted_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  bool hasSameSnapshot(PendingWrittenSubmission other) =>
      assignmentId == other.assignmentId &&
      title == other.title &&
      kind == other.kind &&
      skill == other.skill &&
      targetCount == other.targetCount &&
      correct == other.correct &&
      response == other.response &&
      clientId == other.clientId &&
      submittedAt.toUtc() == other.submittedAt.toUtc();
}

/// Stores written/reading responses separately from drafts until submit_progress
/// confirms the response. Client IDs make network retries idempotent.
class OfflineAssignmentSubmissionQueueService {
  OfflineAssignmentSubmissionQueueService(
    this.userId, {
    SharedPreferences? preferences,
  }) : _preferences = preferences;

  final String userId;
  final SharedPreferences? _preferences;

  String get _storageKey => 'sprachtreppe_pending_written_submissions_v1_$userId';
  String _draftKey(int assignmentId) =>
      'sprachtreppe_assignment_draft_v1_${userId}_$assignmentId';

  Future<SharedPreferences> _resolvePreferences() async {
    final cached = _preferences;
    if (cached != null) return cached;
    return SharedPreferences.getInstance();
  }

  Future<List<PendingWrittenSubmission>> loadAll() async {
    final preferences = await _resolvePreferences();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return [];

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        await preferences.remove(_storageKey);
        return [];
      }

      final result = <PendingWrittenSubmission>[];
      for (final value in decoded.values) {
        if (value is! Map) continue;
        try {
          result.add(
            PendingWrittenSubmission.fromJson(
              Map<String, dynamic>.from(value),
            ),
          );
        } catch (_) {
          // Skip one malformed local record instead of losing other queued work.
        }
      }
      result.sort((a, b) {
        final timeOrder = a.submittedAt.compareTo(b.submittedAt);
        return timeOrder != 0 ? timeOrder : a.assignmentId.compareTo(b.assignmentId);
      });
      return result;
    } catch (_) {
      await preferences.remove(_storageKey);
      return [];
    }
  }

  Future<PendingWrittenSubmission?> loadOne(int assignmentId) async {
    for (final item in await loadAll()) {
      if (item.assignmentId == assignmentId) return item;
    }
    return null;
  }

  Future<PendingWrittenSubmission> enqueue({
    required StudentAssignment assignment,
    required String response,
  }) async {
    final cleanResponse = response.trim();
    if (assignment.id < 1 ||
        cleanResponse.isEmpty ||
        cleanResponse.length > 5000 ||
        assignment.targetCount < 1) {
      throw ArgumentError('The written response or assignment details are invalid.');
    }

    final preferences = await _resolvePreferences();
    final pending = await loadAll();
    final existingIndex = pending.indexWhere((item) => item.assignmentId == assignment.id);
    final existing = existingIndex < 0 ? null : pending[existingIndex];
    final sameSubmission = existing != null &&
        existing.title == assignment.title &&
        existing.kind == assignment.kind &&
        existing.skill == assignment.skill &&
        existing.targetCount == assignment.targetCount &&
        existing.correct == assignment.correct &&
        existing.response == cleanResponse;

    final saved = PendingWrittenSubmission(
      assignmentId: assignment.id,
      title: assignment.title,
      kind: assignment.kind,
      skill: assignment.skill,
      targetCount: assignment.targetCount,
      correct: assignment.correct.clamp(0, assignment.targetCount).toInt(),
      response: cleanResponse,
      clientId: sameSubmission
          ? existing.clientId
          : 'writing-${assignment.id}-${DateTime.now().microsecondsSinceEpoch}',
      submittedAt: sameSubmission ? existing.submittedAt : DateTime.now().toUtc(),
    );

    if (existingIndex < 0) {
      pending.add(saved);
    } else {
      pending[existingIndex] = saved;
    }
    await _save(preferences, pending);
    return saved;
  }

  /// Remove a response only if no newer text replaced the sent snapshot.
  Future<void> clearSynced(PendingWrittenSubmission sent) async {
    final preferences = await _resolvePreferences();
    final pending = await loadAll();
    final index = pending.indexWhere((item) => item.assignmentId == sent.assignmentId);
    if (index < 0 || !pending[index].hasSameSnapshot(sent)) return;

    pending.removeAt(index);
    await _save(preferences, pending);

    // Don't remove a draft the learner edited while the upload was in flight.
    final draft = preferences.getString(_draftKey(sent.assignmentId));
    if (draft?.trim() == sent.response) {
      await preferences.remove(_draftKey(sent.assignmentId));
    }
  }

  Future<void> _save(
    SharedPreferences preferences,
    List<PendingWrittenSubmission> pending,
  ) async {
    if (pending.isEmpty) {
      await preferences.remove(_storageKey);
      return;
    }

    pending.sort((a, b) => a.assignmentId.compareTo(b.assignmentId));
    final encoded = <String, Object>{};
    for (final item in pending) {
      encoded[item.assignmentId.toString()] = item.toStorageJson();
    }
    await preferences.setString(_storageKey, jsonEncode(encoded));
  }
}

int _queueInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
