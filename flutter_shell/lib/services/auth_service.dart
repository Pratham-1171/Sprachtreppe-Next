import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../models/app_user.dart';

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Future<AppUser> loadCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No active session.');
    }

    final profile = await _client
        .from('profiles')
        .select('id, full_name, email, role, approved')
        .eq('id', user.id)
        .single();

    final approved = profile['approved'] as bool? ?? false;
    if (!approved) {
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

    return AppUser(
      id: user.id,
      displayName: displayName?.isNotEmpty == true
          ? displayName!
          : (email?.isNotEmpty == true ? email! : 'User'),
      role: role,
    );
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
      await _client.auth.signOut();
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() => _client.auth.signOut();
}
