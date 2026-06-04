import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:application/main.dart';
import 'package:application/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('First launch can configure a server and reach pairing screen', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Re:Link'), findsOneWidget);
    expect(find.text('Server Address'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'http://127.0.0.1:9');
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Start your session'), findsOneWidget);
    expect(find.text('Create Connection'), findsOneWidget);
    expect(find.text('Join Connection'), findsOneWidget);
  });
}
