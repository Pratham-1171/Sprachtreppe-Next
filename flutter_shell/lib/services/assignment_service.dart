import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student_assignment.dart';

class AssignmentService {
  AssignmentService(this._client);

  final SupabaseClient _client;
  bool _lastLoadUsedCache = false;

  bool get lastLoadUsedCache => _lastLoadUsedCache;

  String _cacheKey(String studentId) => 'sprachtreppe_assignments_cache_v1_$studentId';

  Future<List<StudentAssignment>> loadForStudent(String studentId) async {
    _lastLoadUsedCache = false;
    try {
      return await _loadFromServer(studentId);
    } catch (error) {
      // Cached class/assignment metadata is a local UI fallback only. Do not hide
      // authorization or RLS errors behind stale content.
      if (!isConnectivityFailure(error)) rethrow;
      final cached = await _loadFromCache(studentId);
      if (cached == null) rethrow;
      _lastLoadUsedCache = true;
      return cached;
    }
  }

  Future<List<StudentAssignment>> _loadFromServer(String studentId) async {
    // RLS on assignments_select is the access boundary for student visibility.
    final rawRows = await _client
        .from('assignments')
        .select(
          'id, class_id, title, instructions, kind, skill, target_count, '
          'due_at, created_at, classes(name)',
        )
        .eq('archived', false)
        .order('created_at', ascending: false)
        .limit(100);

    final rows = rawRows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final ids = rows
        .map((row) => row['id'])
        .whereType<num>()
        .map((id) => id.toInt())
        .toList();
    final progressById = <int, Map<String, dynamic>>{};

    if (ids.isNotEmpty) {
      final rawProgress = await _client
          .from('assignment_progress')
          .select('assignment_id, done, correct')
          .eq('student_id', studentId)
          .inFilter('assignment_id', ids);
      for (final value in rawProgress as List) {
        if (value is! Map) continue;
        final row = Map<String, dynamic>.from(value);
        final rawId = row['assignment_id'];
        if (rawId is num) progressById[rawId.toInt()] = row;
      }
    }

    final result = rows.map((row) {
      final rawId = row['id'];
      final id = rawId is num ? rawId.toInt() : int.tryParse(rawId.toString()) ?? 0;
      return StudentAssignment.fromJson(row, progress: progressById[id]);
    }).toList();

    // Storage failure must not turn a successful server read into a failure.
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _cacheKey(studentId),
        encodeCachedRows(rows, progressById),
      );
    } catch (_) {
      // Keep the live server data in memory for this session.
    }

    return result;
  }

  Future<List<StudentAssignment>?> _loadFromCache(String studentId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_cacheKey(studentId));
      if (encoded == null) return null;
      return decodeCachedRows(encoded);
    } catch (_) {
      return null;
    }
  }

  static String encodeCachedRows(
    List<Map<String, dynamic>> rows,
    Map<int, Map<String, dynamic>> progressById,
  ) {
    return jsonEncode({
      'rows': [
        for (final row in rows)
          {
            'assignment': row,
            'progress': _rowId(row['id']) == null ? null : progressById[_rowId(row['id'])!],
          },
      ],
    });
  }

  static List<StudentAssignment> decodeCachedRows(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map || decoded['rows'] is! List) {
      throw const FormatException('Invalid cached assignment list.');
    }
    final result = <StudentAssignment>[];
    for (final value in (decoded['rows'] as List)) {
      if (value is! Map) continue;
      final entry = Map<String, dynamic>.from(value);
      final rawAssignment = entry['assignment'];
      if (rawAssignment is! Map) continue;
      final row = Map<String, dynamic>.from(rawAssignment);
      final rawProgress = entry['progress'];
      final progress = rawProgress is Map ? Map<String, dynamic>.from(rawProgress) : null;
      result.add(StudentAssignment.fromJson(row, progress: progress));
    }
    return result;
  }

  static bool isConnectivityFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('no address associated with hostname') ||
        message.contains('network is unreachable') ||
        message.contains('connection timed out') ||
        message.contains('connection reset') ||
        message.contains('connection refused') ||
        message.contains('handshakeexception');
  }
}

int? _rowId(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
