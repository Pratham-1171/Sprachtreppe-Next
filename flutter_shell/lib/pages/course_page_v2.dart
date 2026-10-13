import 'package:flutter/material.dart';

import '../models/course.dart';
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
    final course = _service.courses.firstWhere((item) => item.level == _level);
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
          Text(course.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(course.subtitle),
          const SizedBox(height: 16),
          ...course.lessons.map((lesson) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(child: Text('${lesson.number}')),
                  title: Text(lesson.title),
                  subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(lesson.topic)),
                  trailing: const Icon(Icons.chevron_right),
                ),
              )),
        ],
      ),
    );
  }
}
