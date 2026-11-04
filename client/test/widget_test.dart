import 'package:client/ui/pin_entry.dart';
import 'package:client/ui/score_ring.dart';
import 'package:client/ui/theme.dart';
import 'package:client/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a widget in the app theme, the same way the real app does.
Widget host(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: Center(child: SingleChildScrollView(child: child))),
  );
}

Future<void> typeDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  group('PinEntry', () {
    testWidgets('six digits call onCompleted with the PIN', (tester) async {
      String? got;
      await tester.pumpWidget(host(PinEntry(onCompleted: (pin) => got = pin)));

      await typeDigits(tester, '493817');

      expect(got, '493817');
    });

    testWidgets('backspace removes the last digit', (tester) async {
      String? got;
      await tester.pumpWidget(host(PinEntry(onCompleted: (pin) => got = pin)));

      await typeDigits(tester, '12');
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump(const Duration(milliseconds: 20));
      await typeDigits(tester, '34567');

      expect(got, '134567');
    });

    testWidgets('does nothing while disabled', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        host(PinEntry(enabled: false, onCompleted: (pin) => calls++)),
      );

      await typeDigits(tester, '493817');

      expect(calls, 0);
    });

    testWidgets('showError clears the dots so the PIN can be typed again', (
      tester,
    ) async {
      final key = GlobalKey<PinEntryState>();
      var calls = 0;
      await tester.pumpWidget(
        host(PinEntry(key: key, onCompleted: (pin) => calls++)),
      );

      await typeDigits(tester, '493817');
      expect(calls, 1);

      final future = key.currentState!.showError();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await future;

      await typeDigits(tester, '493817');
      expect(calls, 2);
    });
  });

  group('Shared widgets', () {
    testWidgets('EmptyState shows its text and the action button', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          EmptyState(
            icon: Icons.lock_rounded,
            title: 'Nothing here yet',
            message: 'Add your first item.',
            actionLabel: 'Add item',
            onAction: () => tapped = true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Add your first item.'), findsOneWidget);

      await tester.tap(find.text('Add item'));
      expect(tapped, isTrue);
    });

    testWidgets('ScoreRing counts up to its score', (tester) async {
      await tester.pumpWidget(host(const ScoreRing(score: 72)));
      await tester.pump(const Duration(milliseconds: 1300));

      expect(find.text('72'), findsOneWidget);
    });

    test('ScoreRing colours follow the score', () {
      const p = Palette.dark;
      expect(ScoreRing.colorFor(p, 30), p.danger);
      expect(ScoreRing.colorFor(p, 60), p.warning);
      expect(ScoreRing.colorFor(p, 80), p.success);
      expect(ScoreRing.colorFor(p, 95), p.accent);
    });
  });
}
