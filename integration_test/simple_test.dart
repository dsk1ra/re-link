import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:application/main.dart';
import 'package:application/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('Submits input and shows Rust greet result', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Enter a name and submit via button
    final input = find.byType(TextField);
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Tom');

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    // Expect the label to show the greet result
    expect(find.text('Hello, Tom!'), findsOneWidget);

    // Input field should be flushed/cleared
    final textField = tester.widget<TextField>(input);
    expect(textField.controller?.text ?? '', '');
  });
}
