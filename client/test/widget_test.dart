import 'package:flutter_test/flutter_test.dart';
import 'package:client/main.dart';

void main() {
  testWidgets('App loads welcome screen test', (WidgetTester tester) async {
    await tester.pumpWidget(const KeyMasterApp());
    expect(find.text('Welcome to KeyMaster'), findsOneWidget);
  });
}