import 'package:flutter_test/flutter_test.dart';
import 'package:abrj_iraq/main.dart';

void main() {
  testWidgets('App starts and displays its title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('IRAQ NETWORK MONITOR'), findsOneWidget);
  });
}
