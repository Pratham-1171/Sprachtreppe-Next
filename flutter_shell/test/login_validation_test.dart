import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sprachtreppe_flutter/pages/login_page.dart';
import 'package:sprachtreppe_flutter/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
    );
  });

  tearDown(() {
    client.dispose();
  });

  Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField && widget.decoration?.labelText == label,
      );

  testWidgets('sign in lets Supabase validate existing shorter passwords',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          authService: AuthService(client),
          onSignedIn: (_) {},
        ),
      ),
    );

    await tester.enterText(field('Email'), 'not-an-email');
    await tester.enterText(field('Password'), 'abc123');
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsNothing);
    expect(find.text('Enter your password'), findsNothing);
  });

  testWidgets('new student passwords still require at least eight characters',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          authService: AuthService(client),
          onSignedIn: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();

    await tester.enterText(field('Full name'), 'Test Student');
    await tester.enterText(field('Email'), 'not-an-email');
    await tester.enterText(field('Password'), 'abc123');
    await tester.enterText(field('Confirm password'), 'abc123');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });
}
