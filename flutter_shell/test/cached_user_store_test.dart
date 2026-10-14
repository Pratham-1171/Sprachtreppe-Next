import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sprachtreppe_flutter/models/app_role.dart';
import 'package:sprachtreppe_flutter/models/app_user.dart';
import 'package:sprachtreppe_flutter/services/auth_service.dart';
import 'package:sprachtreppe_flutter/services/cached_user_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CachedUserStore', () {
    test('round-trips the minimal profile by user id', () async {
      final store = CachedUserStore();
      const user = AppUser(
        id: 'student-1',
        displayName: 'Mira Student',
        role: AppRole.student,
      );

      await store.save(user);
      final cached = await store.load('student-1');

      expect(cached, isNotNull);
      expect(cached!.id, 'student-1');
      expect(cached.displayName, 'Mira Student');
      expect(cached.role, AppRole.student);
    });

    test('does not return another user profile', () async {
      final store = CachedUserStore();
      await store.save(const AppUser(
        id: 'student-1',
        displayName: 'Student One',
        role: AppRole.student,
      ));

      expect(await store.load('student-2'), isNull);
    });

    test('clears a user cache on sign out', () async {
      final store = CachedUserStore();
      await store.save(const AppUser(
        id: 'teacher-1',
        displayName: 'Teacher One',
        role: AppRole.teacher,
      ));

      await store.clear('teacher-1');

      expect(await store.load('teacher-1'), isNull);
    });

    test('discards corrupt or invalid cached profiles', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'sprachtreppe_cached_app_user_v1_student-1',
        '{not valid json',
      );

      expect(await CachedUserStore().load('student-1'), isNull);
      expect(
        preferences.containsKey('sprachtreppe_cached_app_user_v1_student-1'),
        isFalse,
      );
    });
  });

  group('AuthService.isConnectivityFailure', () {
    test('recognises DNS and socket failures', () {
      expect(
        AuthService.isConnectivityFailure(
          Exception('ClientException: SocketException: Failed host lookup'),
        ),
        isTrue,
      );
      expect(
        AuthService.isConnectivityFailure(
          Exception('No address associated with hostname'),
        ),
        isTrue,
      );
    });

    test('does not treat authorization errors as connectivity failures', () {
      expect(
        AuthService.isConnectivityFailure(Exception('permission denied')),
        isFalse,
      );
      expect(
        AuthService.isConnectivityFailure(Exception('account is not approved')),
        isFalse,
      );
    });
  });
}
