import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/services/dashboard_service.dart';

void main() {
  group('AnnouncementSummary.fromRows', () {
    test('puts pinned announcements first and sorts newest first within a group', () {
      final announcements = AnnouncementSummary.fromRows([
        {
          'title': 'Older pinned',
          'body': 'Pinned item',
          'pinned': true,
          'created_at': '2026-10-10T08:00:00Z',
        },
        {
          'title': 'Newest normal',
          'body': 'Normal item',
          'pinned': false,
          'created_at': '2026-10-14T08:00:00Z',
        },
        {
          'title': 'Newest pinned',
          'body': 'Pinned item',
          'pinned': true,
          'created_at': '2026-10-14T09:00:00Z',
        },
        {
          'title': 'Older normal',
          'body': 'Normal item',
          'pinned': false,
          'created_at': '2026-10-09T08:00:00Z',
        },
      ]);

      expect(
        announcements.map((item) => item.title).toList(),
        ['Newest pinned', 'Older pinned', 'Newest normal', 'Older normal'],
      );
    });

    test('caps the merged feed and handles missing optional fields', () {
      final rows = List.generate(
        8,
        (index) => {
          'title': 'Announcement $index',
          'created_at': DateTime.utc(2026, 10, 1 + index).toIso8601String(),
          'pinned': index == 3,
        },
      );

      final announcements = AnnouncementSummary.fromRows(rows, limit: 5);

      expect(announcements, hasLength(5));
      expect(announcements.first.title, 'Announcement 3');
      expect(announcements.first.body, isEmpty);
    });

    test('supports an empty feed and zero limit', () {
      expect(AnnouncementSummary.fromRows([]), isEmpty);
      expect(
        AnnouncementSummary.fromRows([
          {'title': 'Anything'},
        ], limit: 0),
        isEmpty,
      );
    });
  });
}
