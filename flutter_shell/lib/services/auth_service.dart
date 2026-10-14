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

  Future<void> sendCode({
    required String email,
    required bool allowNewStudent,
  }) async {
    await _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: allowNewStudent,
    );
  }

  Future<void> verifyOtpOnly({
    required String email,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.email,
    );
  }

  Future<AppUser> verifyCode({
    required String email,
    required String code,
  }) async {
    await verifyOtpOnly(email: email, code: code);
    try {
      return await loadCurrentUser();
    } catch (_) {
      await signOut();
      rethrow;
    }
  }

  Future<void> completeStudentRegistration({required String fullName}) async {
    await _client.rpc(
      'complete_student_signup',
      params: {'p_full_name': fullName.trim()},
    );
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
