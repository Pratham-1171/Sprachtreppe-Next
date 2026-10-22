import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sprachtreppe_flutter/main.dart';

void main() {
  testWidgets('Sprachtreppe shell opens the course view', (tester) async {
    await tester.pumpWidget(const SprachtreppeApp());

    expect(find.text('Sprachtreppe'), findsOneWidget);
    expect(find.text('German A1–B1'), findsOneWidget);
    expect(find.text('Basics & introductions'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('level selector changes the displayed course modules', (tester) async {
    await tester.pumpWidget(const SprachtreppeApp());

    expect(find.text('Basics & introductions'), findsOneWidget);
    expect(find.text('Past experiences'), findsNothing);

    await tester.tap(find.text('A2'));
    await tester.pumpAndSettle();

    expect(find.text('Past experiences'), findsOneWidget);
    expect(find.text('Basics & introductions'), findsNothing);
  });

  testWidgets('bottom navigation opens practice and profile', (tester) async {
    await tester.pumpWidget(const SprachtreppeApp());

    await tester.tap(find.text('Practice'));
    await tester.pumpAndSettle();
    expect(find.text('Review words and meanings'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sprachtreppe profile'), findsOneWidget);
  });

  testWidgets('shell uses Material 3 components', (tester) async {
    await tester.pumpWidget(const SprachtreppeApp());

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.useMaterial3, isTrue);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
  });
}
