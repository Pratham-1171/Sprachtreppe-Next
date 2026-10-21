import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../models/app_user.dart';
import 'cached_user_store.dart';

class AuthService {
  AuthService(this._client, {CachedUserStore? cachedUsers})
      : _cachedUsers = cachedUsers ?? CachedUserStore();

  final SupabaseClient _client;
  final CachedUserStore _cachedUsers;

  Future<AppUser> loadCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('No active session.');

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
      } catch (_) {}
      await _client.auth.signOut();
      throw const AuthException('Your account is waiting for administrator approval.');
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
    } catch (_) {}
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

  /// Creates a student account and returns whether email confirmation is required.
  /// The UI must still tell students that administrator approval is separate.
  Future<bool> createStudentAccount({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final name = fullName.trim();
    final cleanEmail = email.trim();
    if (name.isEmpty) {
      throw const AuthException('Full name is required.');
    }

    final response = await _client.auth.signUp(
      email: cleanEmail,
      password: password,
      data: {'full_name': name},
    );
    final createdUser = response.user;
    if (createdUser == null) {
      throw const AuthException('Supabase did not return a new account.');
    }
    if (createdUser.identities?.isEmpty == true) {
      throw const AuthException(
        'An account with this email may already exist. Try signing in instead.',
      );
    }

    // A null session commonly means confirmation is enabled. The account may
    // already exist now, so report this state rather than asking the user to
    // repeat signup (which would then fail as a duplicate).
    if (response.session == null) return true;

    // With confirmation disabled, signUp creates a session. Leave the app
    // signed out until the administrator approves the student profile.
    await _client.auth.signOut();
    return false;
  }

  Future<void> signOut() async {
    final userId = _client.auth.currentUser?.id;
    try {
      await _client.auth.signOut();
    } finally {
      if (userId != null) await _cachedUsers.clear(userId);
    }
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
