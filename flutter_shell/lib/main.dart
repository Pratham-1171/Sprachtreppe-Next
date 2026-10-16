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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  String _level = 'A1';
  final levels = const ['A1', 'A2', 'B1'];

  static const modules = {
    'A1': ['Basics & introductions', 'Family & everyday life', 'Food & shopping', 'Time & appointments'],
    'A2': ['Past experiences', 'Work & education', 'Travel & health', 'Grammar practice'],
    'B1': ['Opinions & discussion', 'Work & society', 'Media & communication', 'Exam practice'],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sprachtreppe')),
      body: IndexedStack(index: _index, children: [
        _course(),
        _practice(),
        _profile(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Course'),
          NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: 'Practice'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _course() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('German A1–B1', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text('Learn step by step with short lessons and practice.'),
      const SizedBox(height: 18),
      SegmentedButton<String>(
        segments: levels.map((x) => ButtonSegment(value: x, label: Text(x))).toList(),
        selected: {_level},
        onSelectionChanged: (s) => setState(() => _level = s.first),
      ),
      const SizedBox(height: 18),
      ...modules[_level]!.asMap().entries.map((e) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Text('${e.key + 1}')),
          title: Text(e.value),
          subtitle: const Text('Lesson • vocabulary • grammar • practice'),
          trailing: const Icon(Icons.chevron_right),
        ),
      )),
    ],
  );

  Widget _practice() => ListView(
    padding: const EdgeInsets.all(16),
    children: const [
      Text('Practice', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
      SizedBox(height: 12),
      Card(child: ListTile(leading: Icon(Icons.translate), title: Text('Vocabulary'), subtitle: Text('Review words and meanings'))),
      Card(child: ListTile(leading: Icon(Icons.rule), title: Text('Grammar'), subtitle: Text('Train A1–B1 grammar'))),
      Card(child: ListTile(leading: Icon(Icons.edit_note), title: Text('Exam practice'), subtitle: Text('Mixed questions and mistakes'))),
    ],
  );

  Widget _profile() => const Center(child: Padding(
    padding: EdgeInsets.all(24),
    child: Text('Sprachtreppe profile\n\nThe Flutter shell is ready for the authenticated LMS layer.', textAlign: TextAlign.center),
  ));
}
