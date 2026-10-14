import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardData {
  const DashboardData({
    required this.classes,
    required this.pendingAssignments,
    required this.completedAssignments,
    required this.unreadNotifications,
    required this.recentAnnouncements,
  });

  final List<ClassSummary> classes;
  final List<AssignmentSummary> pendingAssignments;
  final int completedAssignments;
  final int unreadNotifications;
  final List<AnnouncementSummary> recentAnnouncements;

  Map<String, Object?> toCacheJson() => {
        'classes': [
          for (final item in classes)
            {'id': item.id, 'name': item.name},
        ],
        'pending_assignments': [
          for (final item in pendingAssignments)
            {
              'id': item.id,
              'title': item.title,
              'skill': item.skill,
              'due_at': item.dueAt?.toIso8601String(),
              'target_count': item.targetCount,
              'done': item.done,
              'correct': item.correct,
              'class_name': item.className,
            },
        ],
        'completed_assignments': completedAssignments,
        'unread_notifications': unreadNotifications,
        'announcements': [
          for (final item in recentAnnouncements)
            {
              'title': item.title,
              'body': item.body,
              'created_at': item.createdAt?.toIso8601String(),
              'pinned': item.pinned,
            },
        ],
      };

  static DashboardData fromCacheJson(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) throw const FormatException('Invalid dashboard cache.');
    final cache = Map<String, dynamic>.from(decoded);
    List<Map<String, dynamic>> rows(String key) {
      final value = cache[key];
      if (value is! List) return const [];
      return value.whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    }

    int number(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return DashboardData(
      classes: rows('classes').map((row) => ClassSummary(
        id: number(row['id']),
        name: row['name'] as String? ?? 'Class',
      )).toList(),
      pendingAssignments: rows('pending_assignments').map((row) => AssignmentSummary(
        id: number(row['id']),
        title: row['title'] as String? ?? 'Assignment',
        skill: row['skill'] as String? ?? 'Practice',
        dueAt: DateTime.tryParse(row['due_at']?.toString() ?? ''),
        targetCount: number(row['target_count']),
        done: number(row['done']),
        correct: number(row['correct']),
        className: row['class_name'] as String? ?? 'Class',
      )).toList(),
      completedAssignments: number(cache['completed_assignments']),
      unreadNotifications: number(cache['unread_notifications']),
      recentAnnouncements: AnnouncementSummary.fromRows(rows('announcements')),
    );
  }
}

class ClassSummary {
  const ClassSummary({required this.id, required this.name});
  final int id;
  final String name;
}

class AssignmentSummary {
  const AssignmentSummary({
    required this.id,
    required this.title,
    required this.skill,
    required this.dueAt,
    required this.targetCount,
    required this.done,
    required this.correct,
    required this.className,
  });

  final int id;
  final String title;
  final String skill;
  final DateTime? dueAt;
  final int targetCount;
  final int done;
  final int correct;
  final String className;

  bool get completed => targetCount > 0 ? done >= targetCount : done > 0;
}

class AnnouncementSummary {
  const AnnouncementSummary({
    required this.title,
    required this.body,
    required this.createdAt,
    required this.pinned,
  });

  final String title;
  final String body;
  final DateTime? createdAt;
  final bool pinned;

  static List<AnnouncementSummary> fromRows(
    Iterable<dynamic> rows, {
    int limit = 5,
  }) {
    final announcements = rows.whereType<Map>().map((row) {
      final item = Map<String, dynamic>.from(row);
      return AnnouncementSummary(
        title: item['title'] as String? ?? 'Announcement',
        body: item['body'] as String? ?? '',
        createdAt: DateTime.tryParse(item['created_at']?.toString() ?? ''),
        pinned: item['pinned'] as bool? ?? false,
      );
    }).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      });
    return announcements.take(limit < 0 ? 0 : limit).toList();
  }
}

class DashboardService {
  DashboardService(this._client);

  final SupabaseClient _client;
  bool _lastLoadUsedCache = false;

  bool get lastLoadUsedCache => _lastLoadUsedCache;

  String _cacheKey(String studentId) => 'sprachtreppe_dashboard_cache_v1_$studentId';

  Future<DashboardData> load(String studentId) async {
    _lastLoadUsedCache = false;
    try {
      final data = await _loadOnline(studentId);
      // Cache writes are best-effort; don't turn a valid online dashboard into an error.
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(_cacheKey(studentId), jsonEncode(data.toCacheJson()));
      } catch (_) {}
      return data;
    } catch (error) {
      if (!isDashboardConnectivityFailure(error)) rethrow;
      try {
        final preferences = await SharedPreferences.getInstance();
        final encoded = preferences.getString(_cacheKey(studentId));
        if (encoded != null) {
          final cached = DashboardData.fromCacheJson(encoded);
          _lastLoadUsedCache = true;
          return cached;
        }
      } catch (_) {
        // Invalid or unreadable cache is not a substitute for a failed server request.
      }
      rethrow;
    }
  }

  Future<DashboardData> _loadOnline(String studentId) async {
    final memberships = await _client
        .from('class_members')
        .select('class_id, classes(id, name)')
        .eq('student_id', studentId);

    final classIds = <int>[];
    final classNames = <int, String>{};
    for (final row in memberships as List) {
      final classId = row['class_id'] as int?;
      if (classId == null) continue;
      classIds.add(classId);
      final nested = row['classes'];
      if (nested is Map) {
        classNames[classId] = (nested['name'] as String?) ?? 'Class';
      }
    }

    var assignments = <AssignmentSummary>[];
    if (classIds.isNotEmpty) {
      final assignmentRows = await _client
          .from('assignments')
          .select('id, class_id, title, skill, due_at, target_count')
          .inFilter('class_id', classIds)
          .eq('archived', false)
          .order('due_at', ascending: true);

      final assignmentIds = <int>[];
      for (final row in assignmentRows as List) {
        assignmentIds.add(row['id'] as int);
      }

      final progressByAssignment = <int, Map<String, dynamic>>{};
      if (assignmentIds.isNotEmpty) {
        final progressRows = await _client
            .from('assignment_progress')
            .select('assignment_id, done, correct')
            .eq('student_id', studentId)
            .inFilter('assignment_id', assignmentIds);
        for (final row in progressRows as List) {
          progressByAssignment[row['assignment_id'] as int] = row;
        }
      }

      assignments = assignmentRows.map<AssignmentSummary>((row) {
        final id = row['id'] as int;
        final progress = progressByAssignment[id];
        return AssignmentSummary(
          id: id,
          title: (row['title'] as String?) ?? 'Assignment',
          skill: (row['skill'] as String?) ?? 'Practice',
          dueAt: DateTime.tryParse(row['due_at'] as String? ?? ''),
          targetCount: (row['target_count'] as int?) ?? 0,
          done: (progress?['done'] as int?) ?? 0,
          correct: (progress?['correct'] as int?) ?? 0,
          className: classNames[row['class_id'] as int] ?? 'Class',
        );
      }).toList();
    }

    final notifications = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', studentId)
        .isFilter('read_at', null);

    final nowIso = DateTime.now().toUtc().toIso8601String();
    // School-wide announcements have class_id = null, so load them separately
    // from class announcements and merge the two lists before applying the cap.
    final globalAnnouncementRows = await _client
        .from('announcements')
        .select('title, body, pinned, created_at')
        .isFilter('class_id', null)
        .or('expires_at.is.null,expires_at.gt.$nowIso')
        .order('pinned', ascending: false)
        .order('created_at', ascending: false)
        .limit(5);

    final classAnnouncementRows = classIds.isEmpty
        ? const <dynamic>[]
        : await _client
            .from('announcements')
            .select('title, body, pinned, created_at')
            .inFilter('class_id', classIds)
            .or('expires_at.is.null,expires_at.gt.$nowIso')
            .order('pinned', ascending: false)
            .order('created_at', ascending: false)
            .limit(5);

    final allAnnouncementRows = <dynamic>[
      ...(globalAnnouncementRows as List),
      ...classAnnouncementRows,
    ];

    return DashboardData(
      classes: classNames.entries
          .map((entry) => ClassSummary(id: entry.key, name: entry.value))
          .toList(),
      pendingAssignments: assignments.where((a) => !a.completed).take(5).toList(),
      completedAssignments: assignments.where((a) => a.completed).length,
      unreadNotifications: notifications.length,
      recentAnnouncements: AnnouncementSummary.fromRows(allAnnouncementRows),
    );
  }
}


bool isDashboardConnectivityFailure(Object error) {
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
