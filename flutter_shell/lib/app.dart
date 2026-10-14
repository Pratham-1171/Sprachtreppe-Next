import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/app_role.dart';
import 'models/app_user.dart';
import 'pages/learn_page.dart';
import 'pages/login_page.dart';
import 'pages/practice_page.dart';
import 'pages/assignments_page.dart';
import 'pages/student_dashboard_page.dart';
import 'pages/teacher_pages.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

class SprachtreppeApp extends StatefulWidget {
  const SprachtreppeApp({super.key});

  @override
  State<SprachtreppeApp> createState() => _SprachtreppeAppState();
}

class _SprachtreppeAppState extends State<SprachtreppeApp> {
  late final AuthService _authService;
  late final StreamSubscription<AuthState> _authSubscription;
  AppUser? _user;
  bool _loading = true;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(Supabase.instance.client);
    _restoreSession();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session == null && mounted) {
        setState(() {
          _user = null;
          _loading = false;
        });
      }
    });
  }

  Future<void> _restoreSession() async {
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        _user = await _authService.loadCurrentUser();
      }
    } on AuthException catch (error) {
      await Supabase.instance.client.auth.signOut();
      _startupError = error.message;
    } catch (_) {
      _startupError = 'Could not restore your session.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _signedIn(AppUser user) {
    setState(() {
      _user = user;
      _startupError = null;
    });
  }

  Future<void> _signedOut() async {
    await _authService.signOut();
    if (mounted) setState(() => _user = null);
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sprachtreppe',
      theme: AppTheme.light(),
      home: _loading
          ? const _LoadingPage()
          : _user == null
              ? LoginPage(authService: _authService, onSignedIn: _signedIn)
              : RoleShell(user: _user!, onSignOut: _signedOut),
      builder: (context, child) {
        if (_startupError == null || child == null) return child ?? const SizedBox.shrink();
        return Stack(
          children: [
            child,
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _startupError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.user, required this.onSignOut});

  final AppUser user;
  final VoidCallback onSignOut;

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  int index = 0;

  List<_NavItem> get items {
    switch (widget.user.role) {
      case AppRole.student:
        return const [
          _NavItem(Icons.home_outlined, Icons.home, 'Home'),
          _NavItem(Icons.menu_book_outlined, Icons.menu_book, 'Learn'),
          _NavItem(Icons.edit_note_outlined, Icons.edit_note, 'Practice'),
          _NavItem(Icons.assignment_outlined, Icons.assignment, 'Tasks'),
          _NavItem(Icons.person_outline, Icons.person, 'Profile'),
        ];
      case AppRole.teacher:
        return const [
          _NavItem(Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
          _NavItem(Icons.assignment_outlined, Icons.assignment, 'Work'),
          _NavItem(Icons.groups_outlined, Icons.groups, 'Classes'),
          _NavItem(Icons.person_outline, Icons.person, 'Profile'),
        ];
      case AppRole.admin:
        return const [
          _NavItem(Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
          _NavItem(Icons.groups_outlined, Icons.groups, 'Students'),
          _NavItem(Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, 'Admin'),
          _NavItem(Icons.person_outline, Icons.person, 'Profile'),
        ];
    }
  }

  Widget _pageFor(_NavItem item) {
    if (widget.user.role == AppRole.student && item.label == 'Home') {
      return StudentDashboardPage(user: widget.user);
    }
    if (widget.user.role == AppRole.student && item.label == 'Learn') {
      return const LearnPage();
    }
    if (widget.user.role == AppRole.student && item.label == 'Practice') {
      return PracticePage(userId: widget.user.id);
    }
    if (widget.user.role == AppRole.student && item.label == 'Tasks') {
      return AssignmentsPage(userId: widget.user.id);
    }
    if (widget.user.role == AppRole.teacher && item.label == 'Dashboard') {
      return const TeacherDashboardPage();
    }
    if (widget.user.role == AppRole.teacher && item.label == 'Classes') {
      return const TeacherClassesPage();
    }
    if (widget.user.role == AppRole.teacher && item.label == 'Work') {
      return const TeacherWorkPage();
    }
    return _Page(title: item.label, role: widget.user.role);
  }

  @override
  Widget build(BuildContext context) {
    final nav = items;
    if (index >= nav.length) index = 0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('Sprachtreppe', overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              tooltip: 'Account',
              onSelected: (value) {
                if (value == 'signout') widget.onSignOut();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(widget.user.displayName, overflow: TextOverflow.ellipsis),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'signout', child: Text('Sign out')),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.account_circle_outlined),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: index,
          children: nav.map(_pageFor).toList(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: nav
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.role});

  final String title;
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 500 ? 16.0 : 24.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('${role.label} workspace', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: const [
                  _MetricCard(label: 'Progress', value: '0%'),
                  _MetricCard(label: 'Today', value: '0 min'),
                  _MetricCard(label: 'Streak', value: '0 days'),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Authentication is connected', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text('This Flutter screen is protected by Supabase Auth and the profile role. The legacy LMS remains available during migration.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
