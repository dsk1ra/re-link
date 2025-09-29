// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:application/main.dart';

void main() {
  testWidgets('Shows input on top with submit button', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Input field labeled exists
    expect(find.widgetWithText(TextField, 'Enter Your Message'), findsOneWidget);

    // Submit button exists
    expect(find.text('Submit'), findsOneWidget);

    // Result placeholder is visible initially
    expect(find.text('Result will appear here'), findsOneWidget);
  });
}
