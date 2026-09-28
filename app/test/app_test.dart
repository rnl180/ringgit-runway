import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

void main() {
  testWidgets('signed out: sign in with a wrong then right password', (
    tester,
  ) async {
    final api = FakeApi(signedIn: false);
    await pumpApp(tester, api);

    expect(find.text('Ringgit Runway'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'aina@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'wrong pass',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Email or password is wrong.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct horse',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Safe to spend today'), findsOneWidget);
  });

  testWidgets('home shows the budget math for today', (tester) async {
    await pumpApp(tester, FakeApi());

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Safe to spend today'), findsOneWidget);
    // left = 1500 - 665 - 30 - 100 = RM 705; (705 + 15) / 21 = 34.28
    expect(find.byKey(const Key('safeToday')), findsOneWidget);
    expect(find.text('RM 19.28'), findsOneWidget);
    expect(find.text('RM 34.28'), findsOneWidget); // daily budget
    expect(find.text('21'), findsOneWidget); // days left
    expect(find.text('RM 705.00'), findsOneWidget);
    expect(find.text('On track'), findsOneWidget);
    expect(find.text('Bills still due'), findsOneWidget);
    expect(find.text('RM 30.00'), findsOneWidget);
    expect(find.text('Month gone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('month switcher shows a past month as left over', (tester) async {
    await pumpApp(tester, FakeApi());
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('Left over'), findsOneWidget);
    expect(find.text('Safe to spend today'), findsNothing);
    expect(find.text('No income yet'), findsOneWidget);

    await tester.tap(find.text('Tap for this month'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
  });

  testWidgets('carry over is offered when last month had money left', (
    tester,
  ) async {
    final api = FakeApi()..previousLeftOverSen = 12345;
    await pumpApp(tester, api);
    expect(find.text('You had RM 123.45 left in August.'), findsOneWidget);
    expect(find.text('Carry over'), findsOneWidget);
  });

  testWidgets('add an expense: validates, then sends integer sen', (
    tester,
  ) async {
    final api = FakeApi();
    await pumpApp(tester, api);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Save expense'), findsOneWidget);

    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount like 12.50'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '7.90');
    await tester.tap(find.text('Transport'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Note (optional)'),
      'LRT to campus',
    );
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    final post = api.requests.lastWhere((r) => r.method == 'POST');
    expect(jsonDecode(post.body), {
      'kind': 'expense',
      'amountSen': 790,
      'categoryId': 'transport',
      'occurredOn': '2026-09-10',
      'note': 'LRT to campus',
    });
    expect(find.text('Expense of RM 7.90 saved'), findsOneWidget);
    // Home refreshed: 19.28 - 7.90
    expect(find.text('RM 11.38'), findsOneWidget);
  });

  testWidgets('activity groups by day and confirms before deleting', (
    tester,
  ) async {
    final api = FakeApi();
    await pumpApp(tester, api);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Nasi lemak at the cafe'), findsOneWidget);
    expect(find.text('+RM 1,500.00'), findsOneWidget);

    await tester.tap(find.text('Nasi lemak at the cafe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete entry'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this entry?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.requests.where((r) => r.method == 'DELETE'), isEmpty);

    await tester.drag(
      find.text('Nasi lemak at the cafe'),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(api.requests.where((r) => r.method == 'DELETE'), hasLength(1));
    expect(find.text('Nasi lemak at the cafe'), findsNothing);
  });

  testWidgets('insights: chart and category limit warning', (tester) async {
    await pumpApp(tester, FakeApi());
    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();
    expect(find.text('Daily spending'), findsOneWidget);
    expect(find.textContaining('Dashed line: RM 25.66 a day'), findsOneWidget);
    // Food RM 65 against a RM 50 limit
    expect(find.text('RM 65.00 of RM 50'), findsOneWidget);
    expect(find.text('Over limit by RM 15.00'), findsOneWidget);

    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(find.text('5 Sep'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bills: status labels and mark paid', (tester) async {
    final api = FakeApi();
    await pumpApp(tester, api);
    await tester.tap(find.text('Bills & plan'));
    await tester.pumpAndSettle();
    expect(find.text('RM 600.00 · Paid 1 Sep'), findsOneWidget);
    expect(find.text('RM 30.00 · Due in 5 days'), findsOneWidget);
    expect(find.text('RM 100.00 a month'), findsOneWidget);

    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();
    expect(api.requests.any((r) => r.url.path == '/bills/b2/pay'), isTrue);
    expect(find.text('Phone plan marked paid (RM 30.00)'), findsOneWidget);
  });

  testWidgets('dark theme at a small phone width has no overflow', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeApi(),
      platformBrightness: Brightness.dark,
      size: const Size(320, 640),
    );
    expect(find.text('Safe to spend today'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final tab in ['Activity', 'Insights', 'Bills & plan']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
