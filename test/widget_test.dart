import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abrj_iraq/main.dart';

void main() {
  testWidgets('App starts and displays its title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('IRAQ NETWORK MONITOR'), findsOneWidget);
  });

  testWidgets('Main sections remain separate and selectable', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    final navigation = find.byType(NavigationBar);
    expect(navigation, findsOneWidget);

    final destinations = <String, int>{
      'الشبكة': 0,
      'الخريطة': 1,
      'السجل': 2,
      'الأدوات': 3,
    };

    for (final entry in destinations.entries) {
      final destination = find.text(entry.key);
      expect(destination, findsOneWidget);
      await tester.tap(destination);
      await tester.pump();
      expect(
        tester.widget<NavigationBar>(navigation).selectedIndex,
        entry.value,
        reason: 'The ${entry.key} section should be independently selectable.',
      );
    }
  });

  testWidgets('Update control remains reachable in compact settings', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byTooltip('الإعدادات'));
    await tester.pump(const Duration(milliseconds: 400));

    final updateControl = find.text('تحديث التطبيق / فحص التحديثات');
    expect(updateControl, findsOneWidget);

    await tester.ensureVisible(updateControl);
    await tester.pump();

    expect(tester.getRect(updateControl).overlaps(
      tester.getRect(find.byType(SingleChildScrollView).last),
    ), isTrue);
  });
}
