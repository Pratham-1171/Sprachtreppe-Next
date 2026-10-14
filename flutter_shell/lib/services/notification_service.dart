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

  Future<List<AppNotification>> load() async {
    final rows = await _client
        .from('notifications')
        .select('id, kind, title, body, link, created_at, read_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);

    return (rows as List)
        .whereType<Map>()
        .map((row) => AppNotification.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> markRead(int notificationId) async {
    await _client.rpc(
      'mark_notification_read',
      params: {'p_id': notificationId},
    );
  }
}
