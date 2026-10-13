import 'package:flutter/material.dart';

import '../models/course_module.dart';
import '../services/course_service.dart';

class CoursePageV2 extends StatefulWidget {
  const CoursePageV2({super.key});

  @override
  State<CoursePageV2> createState() => _CoursePageV2State();
}

class _CoursePageV2State extends State<CoursePageV2> {
  final CourseService _service = const CourseService();
  String _level = 'A1';

  @override
  Widget build(BuildContext context) {
    final modules = _service.modules.where((module) => module.level == _level).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Deutsch lernen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'A1', label: Text('A1')),
              ButtonSegment(value: 'A2', label: Text('A2')),
              ButtonSegment(value: 'B1', label: Text('B1')),
            ],
            selected: {_level},
            onSelectionChanged: (selection) => setState(() => _level = selection.first),
          ),
          const SizedBox(height: 16),
          ...modules.map((module) => _ModuleCard(module: module)),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final CourseModule module;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(module.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(module.description),
            const SizedBox(height: 12),
            ...module.topics.asMap().entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text('${entry.key + 1}'),
                    ),
                    title: Text(entry.value),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
