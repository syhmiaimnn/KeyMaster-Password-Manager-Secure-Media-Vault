import 'package:client/main.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first run shows the PIN setup screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      DevicePreview(
        enabled: false,
        builder: (context) => const KeyMasterApp(hasPin: false),
      ),
    );

    expect(find.text('Create Your Master PIN'), findsOneWidget);
  });

  testWidgets('a PIN shorter than 6 digits is rejected', (WidgetTester tester) async {
    await tester.pumpWidget(
      DevicePreview(
        enabled: false,
        builder: (context) => const KeyMasterApp(hasPin: false),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '123');
    await tester.tap(find.text('Save Master PIN'));
    await tester.pump();

    expect(find.text('PIN must be at least 6 digits long.'), findsOneWidget);
  });
}