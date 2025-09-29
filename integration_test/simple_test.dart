import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:application/main.dart';
import 'package:application/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('Maintains a buffer of 10 newest greet messages', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    final input = find.byType(TextField);
    expect(input, findsOneWidget);

    // Submit 12 messages
    for (var i = 1; i <= 12; i++) {
      await tester.enterText(input, 'Name $i');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
    }

  // Buffer accepts only 10 messages; further submissions are ignored.
  // After 12 attempts, buffer should contain Name 1..Name 10 (newest-first => Name 10 at top)
  expect(find.text('Hello, Name 12!'), findsNothing);
  expect(find.text('Hello, Name 11!'), findsNothing);
  expect(find.text('Hello, Name 10!'), findsOneWidget);
  expect(find.text('Hello, Name 9!'), findsOneWidget);
  expect(find.text('Hello, Name 8!'), findsOneWidget);
  expect(find.text('Hello, Name 7!'), findsOneWidget);
  expect(find.text('Hello, Name 6!'), findsOneWidget);
  expect(find.text('Hello, Name 5!'), findsOneWidget);
  expect(find.text('Hello, Name 4!'), findsOneWidget);
  expect(find.text('Hello, Name 3!'), findsOneWidget);
  expect(find.text('Hello, Name 2!'), findsOneWidget);
  expect(find.text('Hello, Name 1!'), findsOneWidget);

    // Verify order on screen is newest first (Name 10 at top)
    final tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(10));
    var firstTile = tester.widget<ListTile>(tiles.first);
    expect((firstTile.title as Text).data, 'Hello, Name 10!');

    // Now consume the newest message using the Consume button; it should remove Name 10
    await tester.tap(find.text('Consume'));
    await tester.pumpAndSettle();

    // Now there should still be 9 messages; Name 10 should be gone and Name 9 should be first
    expect(find.text('Hello, Name 10!'), findsNothing);
    final tilesAfterConsume = find.byType(ListTile);
    expect(tilesAfterConsume, findsNWidgets(9));
    firstTile = tester.widget<ListTile>(tilesAfterConsume.first);
    expect((firstTile.title as Text).data, 'Hello, Name 9!');
  });
}
