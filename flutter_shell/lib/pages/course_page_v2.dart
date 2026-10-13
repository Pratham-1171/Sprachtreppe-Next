import 'package:flutter/material.dart';

import '../models/course_module.dart';
import '../services/course_service.dart';

class CoursePageV2 extends StatefulWidget {
  const CoursePageV2({super.key});

  @override
  State<CoursePageV2> createState() => _CoursePageV2State();
}

class _CoursePageV2State extends State<CoursePageV2> {
  final CourseService _courseService = CourseService();
  String _level = 'A1';

  List<CourseModule> get _modules => _courseService.modulesForLevel(_level);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('German Course', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('Choose a level and continue learning step by step.', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'A1', label: Text('A1')),
            ButtonSegment(value: 'A2', label: Text('A2')),
            ButtonSegment(value: 'B1', label: Text('B1')),
          ],
          selected: {_level},
          onSelectionChanged: (selection) => setState(() => _level = selection.first),
        ),
        const SizedBox(height: 20),
        ..._modules.map((module) => Card(
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
                    ...module.topics.map((topic) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(topic),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {},
                        )),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}
