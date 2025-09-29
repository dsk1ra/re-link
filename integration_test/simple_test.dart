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

    // Only 10 newest should be visible: 3..12 -> but capped to 10 means 3 is dropped, 4..12 remain (newest first)
    expect(find.text('Hello, Name 12!'), findsOneWidget);
    expect(find.text('Hello, Name 11!'), findsOneWidget);
    expect(find.text('Hello, Name 10!'), findsOneWidget);
    expect(find.text('Hello, Name 9!'), findsOneWidget);
    expect(find.text('Hello, Name 8!'), findsOneWidget);
    expect(find.text('Hello, Name 7!'), findsOneWidget);
    expect(find.text('Hello, Name 6!'), findsOneWidget);
    expect(find.text('Hello, Name 5!'), findsOneWidget);
    expect(find.text('Hello, Name 4!'), findsOneWidget);
    expect(find.text('Hello, Name 3!'), findsNothing);
    expect(find.text('Hello, Name 2!'), findsNothing);
    expect(find.text('Hello, Name 1!'), findsNothing);

    // Verify order on screen is newest first (12 at top). We can check by
    // ensuring the first ListTile's title matches the newest message.
    final tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(10));
    final firstTile = tester.widget<ListTile>(tiles.first);
    expect((firstTile.title as Text).data, 'Hello, Name 12!');
  });
}
