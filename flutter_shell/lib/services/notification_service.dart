import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.link,
    required this.createdAt,
    required this.readAt,
  });

  final int id;
  final String kind;
  final String title;
  final String body;
  final String? link;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'link': link,
        'created_at': createdAt?.toUtc().toIso8601String(),
        'read_at': readAt?.toUtc().toIso8601String(),
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] as num).toInt(),
      kind: json['kind'] as String? ?? 'info',
      title: json['title'] as String? ?? 'Notification',
      body: json['body'] as String? ?? '',
      link: json['link'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
    );
  }
}

class NotificationService {
  NotificationService(this._client, this.userId);

  final SupabaseClient _client;
  final String userId;
  bool _lastLoadUsedCache = false;

  bool get lastLoadUsedCache => _lastLoadUsedCache;

  String _cacheKey(String userId) => 'sprachtreppe_notifications_cache_v1_$userId';

  Future<List<AppNotification>> load() async {
    _lastLoadUsedCache = false;
    try {
      final rows = await _client
          .from('notifications')
          .select('id, kind, title, body, link, created_at, read_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);

      final notifications = (rows as List)
          .whereType<Map>()
          .map((row) => AppNotification.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      // Do not fail a live read because local cache storage is unavailable.
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
          _cacheKey(userId),
          encodeCachedNotifications(notifications),
        );
      } catch (_) {}
      return notifications;
    } catch (error) {
      // Cache is only a local display fallback for connectivity failures; it
      // must never conceal an RLS, permission, or account-state error.
      if (!isConnectivityFailure(error)) rethrow;
      try {
        final preferences = await SharedPreferences.getInstance();
        final encoded = preferences.getString(_cacheKey(userId));
        if (encoded != null) {
          final cached = decodeCachedNotifications(encoded);
          _lastLoadUsedCache = true;
          return cached;
        }
      } catch (_) {
        // Invalid cache is not a substitute for the failed server request.
      }
      rethrow;
    }
  }

  Future<void> markRead(int notificationId) async {
    await _client.rpc(
      'mark_notification_read',
      params: {'p_id': notificationId},
    );

    // Keep the cached badge/inbox consistent after a server-confirmed update.
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_cacheKey(userId));
      if (encoded == null) return;
      final notifications = decodeCachedNotifications(encoded);
      final index = notifications.indexWhere((item) => item.id == notificationId);
      if (index < 0) return;
      final item = notifications[index];
      notifications[index] = AppNotification(
        id: item.id,
        kind: item.kind,
        title: item.title,
        body: item.body,
        link: item.link,
        createdAt: item.createdAt,
        readAt: DateTime.now().toUtc(),
      );
      await preferences.setString(
        _cacheKey(userId),
        encodeCachedNotifications(notifications),
      );
    } catch (_) {
      // A cache write cannot reverse a confirmed server-side mark-read.
    }
  }

  static String encodeCachedNotifications(List<AppNotification> notifications) =>
      jsonEncode(notifications.map((item) => item.toJson()).toList());

  static List<AppNotification> decodeCachedNotifications(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Invalid cached notifications.');
    }
    return decoded
        .whereType<Map>()
        .map((row) => AppNotification.fromJson(Map<String, dynamic>.from(row)))
        .toList();
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
