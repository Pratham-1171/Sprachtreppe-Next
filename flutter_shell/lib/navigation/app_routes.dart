import '../models/app_role.dart';

class AppRoute {
  const AppRoute(this.path, this.title, {this.roles = const {}});

  final String path;
  final String title;
  final Set<AppRole> roles;

  bool allowedFor(AppRole role) => roles.isEmpty || roles.contains(role);
}

class AppRoutes {
  static const home = AppRoute('/home', 'Home');
  static const learn = AppRoute('/learn', 'Learn', roles: {AppRole.student});
  static const practice = AppRoute('/practice', 'Practice', roles: {AppRole.student});
  static const assignments = AppRoute('/assignments', 'Assignments');
  static const classes = AppRoute('/classes', 'Classes', roles: {AppRole.teacher, AppRole.admin});
  static const students = AppRoute('/students', 'Students', roles: {AppRole.teacher, AppRole.admin});
  static const admin = AppRoute('/admin', 'Administration', roles: {AppRole.admin});
  static const profile = AppRoute('/profile', 'Profile');
}
