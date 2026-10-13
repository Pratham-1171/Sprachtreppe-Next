import 'package:flutter/material.dart';

void main() => runApp(const SprachtreppeApp());

class SprachtreppeApp extends StatelessWidget {
  const SprachtreppeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sprachtreppe',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  final pages = const [HomePage(), LearnPage(), PracticePage(), ProfilePage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sprachtreppe', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_outlined)),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Learn'),
          NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: 'Practice'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _WelcomeCard(),
          SizedBox(height: 16),
          Text('Continue learning', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          SizedBox(height: 10),
          _ProgressCard(title: 'German A2', subtitle: 'Netzwerk neu • Grammar', progress: .62),
          SizedBox(height: 12),
          _ProgressCard(title: 'Vocabulary', subtitle: 'Daily review', progress: .38),
          SizedBox(height: 16),
          Text('Quick actions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          SizedBox(height: 10),
          _ActionCard(icon: Icons.style_outlined, title: 'Vocabulary review', subtitle: 'Review today’s words'),
          SizedBox(height: 10),
          _ActionCard(icon: Icons.edit_note_outlined, title: 'Grammar practice', subtitle: 'Practice A2 topics'),
        ],
      );
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('Guten Tag! 👋', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Ready for a little German today?'),
          ]),
        ),
      );
}

class _ProgressCard extends StatelessWidget {
  final String title, subtitle;
  final double progress;
  const _ProgressCard({required this.title, required this.subtitle, required this.progress});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, minHeight: 7, borderRadius: BorderRadius.circular(8)),
          ]),
        ),
      );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _ActionCard({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}

class LearnPage extends StatelessWidget {
  const LearnPage({super.key});
  @override
  Widget build(BuildContext context) => const _PlaceholderPage(icon: Icons.menu_book, title: 'Learn', text: 'A1–B1 courses will be migrated here step by step.');
}

class PracticePage extends StatelessWidget {
  const PracticePage({super.key});
  @override
  Widget build(BuildContext context) => const _PlaceholderPage(icon: Icons.quiz, title: 'Practice', text: 'Exercises and exam practice will be migrated here.');
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => const _PlaceholderPage(icon: Icons.person, title: 'Profile', text: 'Authentication, progress and settings will be connected later.');
}

class _PlaceholderPage extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const _PlaceholderPage({required this.icon, required this.title, required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 54),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ]),
        ),
      );
}
