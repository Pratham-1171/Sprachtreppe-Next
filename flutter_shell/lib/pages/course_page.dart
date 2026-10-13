import 'package:flutter/material.dart';

import '../models/course_module.dart';
import '../services/course_service.dart';

class CoursePage extends StatefulWidget {
  const CoursePage({super.key});

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  final _service = const CourseService();
  String _level = 'All';

  List<CourseModule> get _filtered => _level == 'All'
      ? _service.modules
      : _service.modules.where((module) => module.level == _level).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 500 ? 16.0 : 24.0;
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 28),
            children: [
              Text('Course', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Learn German from A1 to B1 with focused grammar and practical progression.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'All', label: Text('All')),
                  ButtonSegment(value: 'A1', label: Text('A1')),
                  ButtonSegment(value: 'A2', label: Text('A2')),
                  ButtonSegment(value: 'B1', label: Text('B1')),
                ],
                selected: {_level},
                onSelectionChanged: (value) => setState(() => _level = value.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 16),
              ..._filtered.map((module) => _ModuleCard(module: module)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.construction_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Course migration is incremental. The legacy lesson engine stays available until these Flutter lessons are fully migrated and verified.',
                        ),
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

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final CourseModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('${module.level} · ${module.title}'),
        subtitle: Text(module.description),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Topics', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          ...module.topics.map(
            (topic) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle_outline, size: 20, color: theme.colorScheme.primary),
              title: Text(topic),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }
}
