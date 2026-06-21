// Basic smoke test for the Panki app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:panki_ai/main.dart';

void main() {
  testWidgets('App launches and shows Connect tab', (WidgetTester tester) async {
    await tester.pumpWidget(const PankiApp());
    await tester.pump();

    expect(find.text('PANKI'), findsOneWidget);
    expect(find.byIcon(Icons.settings_ethernet), findsOneWidget);
  });
}
