import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_role.dart';
import '../models/app_user.dart';

/// Stores only the minimal profile needed to open local learning content offline.
///
/// This cache is for local UI restoration only. Supabase Auth and RLS still
/// protect every server-side read or mutation.
class CachedUserStore {
  CachedUserStore({SharedPreferences? preferences}) : _preferences = preferences;

  final SharedPreferences? _preferences;

  String _key(String userId) => 'sprachtreppe_cached_app_user_v1_$userId';

  Future<SharedPreferences> _resolvePreferences() async {
    final cached = _preferences;
    if (cached != null) return cached;
    return SharedPreferences.getInstance();
  }

  Future<void> save(AppUser user) async {
    final preferences = await _resolvePreferences();
    await preferences.setString(
      _key(user.id),
      jsonEncode({
        'id': user.id,
        'display_name': user.displayName,
        'role': user.role.name,
      }),
    );
  }

  Future<AppUser?> load(String userId) async {
    final preferences = await _resolvePreferences();
    final encoded = preferences.getString(_key(userId));
    if (encoded == null) return null;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        await preferences.remove(_key(userId));
        return null;
      }
      final data = Map<String, dynamic>.from(decoded);
      if (data['id'] != userId) {
        await preferences.remove(_key(userId));
        return null;
      }

      AppRole? role;
      for (final candidate in AppRole.values) {
        if (candidate.name == data['role']) {
          role = candidate;
          break;
        }
      }
      if (role == null) {
        await preferences.remove(_key(userId));
        return null;
      }

      final displayName = (data['display_name'] as String?)?.trim();
      return AppUser(
        id: userId,
        displayName: displayName?.isNotEmpty == true ? displayName! : 'User',
        role: role,
      );
    } catch (_) {
      await preferences.remove(_key(userId));
      return null;
    }
  }

  Future<void> clear(String userId) async {
    final preferences = await _resolvePreferences();
    await preferences.remove(_key(userId));
  }
}
