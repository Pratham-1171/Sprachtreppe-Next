import 'package:flutter/material.dart';

import 'models/app_role.dart';
import 'models/app_user.dart';
import 'theme/app_theme.dart';

class SprachtreppeApp extends StatefulWidget {
  const SprachtreppeApp({super.key});

  @override
  State<SprachtreppeApp> createState() => _SprachtreppeAppState();
}

class _SprachtreppeAppState extends State<SprachtreppeApp> {
  AppRole role = AppRole.student;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sprachtreppe',
      theme: AppTheme.light(),
      home: RoleShell(
        user: AppUser(id: 'demo', displayName: 'Demo User', role: role),
        onRoleChanged: (value) => setState(() => role = value),
      ),
    );
  }
}

class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.user, required this.onRoleChanged});

  final AppUser user;
  final ValueChanged<AppRole> onRoleChanged;

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

  @override
  Widget build(BuildContext context) {
    final nav = items;
    if (index >= nav.length) index = 0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('Sprachtreppe', overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<AppRole>(
            tooltip: 'Demo role',
            onSelected: widget.onRoleChanged,
            itemBuilder: (context) => AppRole.values
                .map((role) => PopupMenuItem(value: role, child: Text(role.label)))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Chip(label: Text(widget.user.role.label)),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: index,
          children: nav.map((item) => _Page(title: item.label, role: widget.user.role)).toList(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: nav
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                ))
            .toList(),
      ),
    );
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
              Text(
                '${role.label} workspace',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
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
                      Text('Ready for the next step?', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text('This Flutter screen is intentionally independent of the legacy LMS. Features will be migrated here one at a time.'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continue'),
                      ),
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
