import 'app_role.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.role,
  });

  final String id;
  final String displayName;
  final AppRole role;
}
