import 'package:flutter_test/flutter_test.dart';
import 'package:sprachtreppe_flutter/services/learning_state_sync_service.dart';
import 'package:sprachtreppe_flutter/services/progress_service.dart';

void main() {
  group('LearningStateSyncService.mergeEvents', () {
    test('unions events from offline devices and de-duplicates retry IDs', () {
      final remote = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'answer-a',
          'timestamp': '2026-10-15T08:00:00Z',
          'correct': true,
        },
        <String, dynamic>{
          'id': 'answer-b',
          'timestamp': '2026-10-15T08:02:00Z',
          'correct': false,
        },
      ];
      final local = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'answer-a',
          'timestamp': '2026-10-15T08:00:00Z',
          'correct': true,
        },
        <String, dynamic>{
          'id': 'answer-c',
          'timestamp': '2026-10-15T08:01:00Z',
          'correct': true,
        },
      ];

      final merged = LearningStateSyncService.mergeEvents(remote, local);

      expect(merged.map((event) => event['id']).toSet(),
          {'answer-a', 'answer-b', 'answer-c'});
      expect(merged, hasLength(3), reason: 'retried event IDs must not be counted twice');
      expect(merged.first['id'], 'answer-a');
      expect(merged.last['id'], 'answer-b');
    });

    test('splits large offline queues into batches without dropping answers', () {
      final events = List<Map<String, dynamic>>.generate(
        1201,
        (index) => <String, dynamic>{
          'id': 'answer-$index',
          'timestamp': DateTime.utc(2026, 10, 15).add(Duration(seconds: index)).toIso8601String(),
        },
      );
      final batches = LearningStateSyncService.batchEvents(events);
      expect(batches.map((batch) => batch.length).toList(), [500, 500, 201]);
      expect(batches.expand((batch) => batch).map((event) => event['id']).toSet(),
          events.map((event) => event['id']).toSet());
    });

    test('keeps the latest version of a colliding event ID', () {
      final merged = LearningStateSyncService.mergeEvents(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'answer-a',
            'timestamp': '2026-10-15T08:00:00Z',
            'correct': false,
          },
        ],
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'answer-a',
            'timestamp': '2026-10-15T08:01:00Z',
            'correct': true,
          },
        ],
      );
      expect(merged, hasLength(1));
      expect(merged.single['correct'], isTrue);
    });
  });


  test('server acknowledgement removes only confirmed offline answers', () {
    final pending = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'answer-a', 'timestamp': '2026-10-15T08:00:00Z'},
      <String, dynamic>{'id': 'answer-b', 'timestamp': '2026-10-15T08:01:00Z'},
      <String, dynamic>{'id': 'answer-c', 'timestamp': '2026-10-15T08:02:00Z'},
    ];

    final remaining = LearningStateSyncService.withoutAcknowledgedEvents(
      pending,
      <String>{'answer-a', 'answer-b'},
    );

    expect(remaining.map((event) => event['id']).toList(), ['answer-c']);
    expect(pending, hasLength(3), reason: 'acknowledgement must not mutate the original queue');
  });

  test('an empty or partial acknowledgement never clears unconfirmed work', () {
    final pending = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'answer-a'},
      <String, dynamic>{'id': 'answer-b'},
    ];

    expect(
      LearningStateSyncService.withoutAcknowledgedEvents(pending, <String>{}),
      hasLength(2),
    );
    expect(
      LearningStateSyncService.withoutAcknowledgedEvents(pending, <String>{'answer-a'})
          .map((event) => event['id']).toList(),
      ['answer-b'],
    );
  });


  test('web course sessions import with stable IDs for cross-device history', () {
    final raw = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'web-session:2026-10-15',
        'date': '2026-10-15',
        'mode': 'Quiz',
        'level': 'A2',
        'questions': 8,
        'correct': 6,
        'duration': 90,
      },
      <String, dynamic>{
        'id': 'flutter-session:native-session-a',
        'date': '2026-10-15',
        'mode': 'Grammar',
        'level': 'A2',
        'questions': 5,
        'correct': 4,
      },
    ];
    final first = LearningStateSyncService.readWebSessionsFromState(raw);
    final second = LearningStateSyncService.readWebSessionsFromState(raw);

    expect(first, hasLength(2));
    expect(first.first.stableId, 'web-session:2026-10-15');
    expect(first.first.stableId, second.first.stableId);
    expect(first.first.total, 8);
    expect(first.first.correct, 6);
    expect(first.first.level, 'A2');
    expect(first.last.stableId, 'native-session-a',
        reason: 'a native session sent through browser history must retain its original ID');
  });

  test('malformed web course history is skipped without discarding valid sessions', () {
    final imported = LearningStateSyncService.readWebSessionsFromState(<Object>[
      <String, Object>{'id': 'bad', 'date': 'not-a-date', 'questions': 5, 'correct': 2},
      <String, Object>{'id': 'valid', 'date': '2026-10-15', 'questions': 4, 'correct': 3},
    ]);

    expect(imported, hasLength(1));
    expect(imported.single.stableId, 'valid');
    expect(imported.single.total, 4);
  });

  test('legacy study sessions acquire a deterministic ID for safe import', () {
    final legacy = <String, dynamic>{
      'completedAt': '2026-10-15T08:00:00Z',
      'mode': 'Grammar',
      'level': 'A2',
      'correct': 4,
      'total': 5,
    };
    final first = StudySession.fromJson(legacy);
    final second = StudySession.fromJson(legacy);
    expect(first.stableId, isNotEmpty);
    expect(first.stableId, second.stableId);
    expect(StudySession.fromJson(first.toJson()).stableId, first.stableId);
  });
}
