import 'package:supabase_flutter/supabase_flutter.dart';

import 'cached_user_store.dart';

import '../models/app_role.dart';
import '../models/app_user.dart';

class AuthService {
  AuthService(this._client, {CachedUserStore? cachedUsers})
      : _cachedUsers = cachedUsers ?? CachedUserStore();

  final SupabaseClient _client;
  final CachedUserStore _cachedUsers;

  Future<AppUser> loadCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No active session.');
    }

    final Map<String, dynamic> profile;
    try {
      profile = await _client
          .from('profiles')
          .select('id, full_name, email, role, approved')
          .eq('id', user.id)
          .single();
    } catch (error) {
      if (isConnectivityFailure(error)) {
        final cachedUser = await _cachedUsers.load(user.id);
        if (cachedUser != null) return cachedUser;
      }
      rethrow;
    }

    final approved = profile['approved'] as bool? ?? false;
    if (!approved) {
      try {
        await _cachedUsers.clear(user.id);
      } catch (_) {
        // A cache cleanup failure must not keep an unapproved session active.
      }
      await _client.auth.signOut();
      throw const AuthException(
        'Your account is waiting for administrator approval.',
      );
    }

    final roleName = profile['role'] as String? ?? 'student';
    final role = AppRole.values.firstWhere(
      (value) => value.name == roleName,
      orElse: () => AppRole.student,
    );

    final displayName = (profile['full_name'] as String?)?.trim();
    final email = (profile['email'] as String?)?.trim();

    final appUser = AppUser(
      id: user.id,
      displayName: displayName?.isNotEmpty == true
          ? displayName!
          : (email?.isNotEmpty == true ? email! : 'User'),
      role: role,
    );
    try {
      await _cachedUsers.save(appUser);
    } catch (_) {
      // Local caching must not block a valid online sign-in.
    }
    return appUser;
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    try {
      return await loadCurrentUser();
    } catch (_) {
      await signOut();
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() async {
    final userId = _client.auth.currentUser?.id;
    try {
      await _client.auth.signOut();
    } finally {
      if (userId != null) {
        await _cachedUsers.clear(userId);
      }
    }
  }

  /// Only connectivity failures may use the last approved profile cache.
  /// Authorization, approval and server errors must not be hidden by stale data.
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
