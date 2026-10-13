enum AppRole {
  student,
  teacher,
  admin,
}

extension AppRoleLabel on AppRole {
  String get label {
    switch (this) {
      case AppRole.student:
        return 'Student';
      case AppRole.teacher:
        return 'Teacher';
      case AppRole.admin:
        return 'Admin';
    }
  }
}
