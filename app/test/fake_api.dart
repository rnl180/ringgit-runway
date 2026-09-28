import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ringgit_runway/data/api_client.dart';
import 'package:ringgit_runway/data/token_store.dart';
import 'package:ringgit_runway/main.dart';
import 'package:ringgit_runway/state/providers.dart';
import 'package:runway_core/runway_core.dart';

final testToday = LocalDate(2026, 9, 10);

const categoriesJson = [
  {'id': 'food', 'kind': 'expense', 'label': 'Food & drinks', 'sortOrder': 10},
  {'id': 'transport', 'kind': 'expense', 'label': 'Transport', 'sortOrder': 30},
  {
    'id': 'housing',
    'kind': 'expense',
    'label': 'Rent & utilities',
    'sortOrder': 40,
  },
  {
    'id': 'phone',
    'kind': 'expense',
    'label': 'Phone & internet',
    'sortOrder': 50,
  },
  {'id': 'allowance', 'kind': 'income', 'label': 'Allowance', 'sortOrder': 10},
  {
    'id': 'carry_over',
    'kind': 'income',
    'label': 'Carried over',
    'sortOrder': 50,
  },
];

Map<String, Object?> entryJson(
  String id,
  String kind,
  int sen,
  String cat,
  String on, {
  String? note,
  String? billId,
}) => {
  'id': id,
  'kind': kind,
  'amountSen': sen,
  'categoryId': cat,
  'note': note,
  'occurredOn': on,
  'billId': billId,
  'createdAt': '2026-09-10T00:00:00Z',
};

/// An in-memory stand-in for the API with September's numbers from the
/// budget tests: RM 1,500 allowance, rent paid, phone plan due.
class FakeApi {
  final requests = <http.Request>[];
  bool signedIn;
  List<Map<String, Object?>> entries = [
    entryJson(
      'e1',
      'income',
      150000,
      'allowance',
      '2026-09-01',
      note: 'Monthly allowance',
    ),
    entryJson(
      'e2',
      'expense',
      60000,
      'housing',
      '2026-09-01',
      note: 'Rent',
      billId: 'b1',
    ),
    entryJson('e3', 'expense', 2000, 'food', '2026-09-01'),
    entryJson('e4', 'expense', 3000, 'food', '2026-09-05'),
    entryJson(
      'e5',
      'expense',
      1500,
      'food',
      '2026-09-10',
      note: 'Nasi lemak at the cafe',
    ),
  ];
  int previousLeftOverSen = 0;

  FakeApi({this.signedIn = true});

  List<Map<String, Object?>> bills(String month) => [
    {
      'id': 'b1',
      'name': 'Rent',
      'amountSen': 60000,
      'dueDay': 1,
      'categoryId': 'housing',
      'active': true,
      'paidOn':
          entries.any(
            (e) =>
                e['billId'] == 'b1' && '${e['occurredOn']}'.startsWith(month),
          )
          ? '$month-01'
          : null,
    },
    {
      'id': 'b2',
      'name': 'Phone plan',
      'amountSen': 3000,
      'dueDay': 15,
      'categoryId': 'phone',
      'active': true,
      'paidOn': null,
    },
  ];

  static const user = {
    'id': 'u1',
    'email': 'aina@example.com',
    'displayName': 'Aina',
    'currency': 'MYR',
    'monthlySavingsGoalSen': 10000,
    'createdAt': '2026-09-01T00:00:00Z',
  };

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    if (path == '/auth/login') {
      final b = jsonDecode(r.body) as Map;
      if (b['password'] != 'correct horse') {
        return _json({
          'error': {
            'code': 'wrong_credentials',
            'message': 'Email or password is wrong.',
          },
        }, 401);
      }
      signedIn = true;
      return _json({'token': 'tok', 'user': user});
    }
    if (!signedIn || r.headers['authorization'] != 'Bearer tok') {
      return _json({
        'error': {'code': 'unauthorized', 'message': 'Please sign in again.'},
      }, 401);
    }
    if (path == '/me') return _json({'user': user});
    if (path == '/categories') return _json({'categories': categoriesJson});
    if (path.startsWith('/months/') && r.method == 'GET') {
      final m = path.substring('/months/'.length);
      return _json({
        'month': m,
        'savingsGoalSen': 10000,
        'entries':
            entries.where((e) => '${e['occurredOn']}'.startsWith(m)).toList()
              ..sort(
                (a, b) => '${b['occurredOn']}'.compareTo('${a['occurredOn']}'),
              ),
        'bills': bills(m),
        'limits': [
          {'categoryId': 'food', 'monthlyLimitSen': 5000},
        ],
        'carryOver': {
          'fromMonth': '',
          'previousLeftOverSen': previousLeftOverSen,
          'alreadyCarried': false,
        },
      });
    }
    if (path == '/transactions' && r.method == 'POST') {
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      final e = entryJson(
        'n${entries.length}',
        b['kind'] as String,
        b['amountSen'] as int,
        b['categoryId'] as String,
        b['occurredOn'] as String,
        note: b['note'] as String?,
      );
      entries.add(e);
      return _json({'transaction': e}, 201);
    }
    if (path.startsWith('/transactions/') && r.method == 'DELETE') {
      entries.removeWhere((e) => e['id'] == path.split('/').last);
      return http.Response('', 204);
    }
    if (path == '/bills/b2/pay') {
      entries.add(
        entryJson(
          'p2',
          'expense',
          3000,
          'phone',
          '2026-09-10',
          note: 'Phone plan',
          billId: 'b2',
        ),
      );
      return _json({'transaction': entries.last}, 201);
    }
    return _json({
      'error': {'code': 'not_found', 'message': 'nope'},
    }, 404);
  }
}

/// Pumps the whole app at phone size against [api].
Future<void> pumpApp(
  WidgetTester tester,
  FakeApi api, {
  Brightness? platformBrightness,
  Size size = const Size(360, 780),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  if (platformBrightness != null) {
    tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
  }
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://api', client: MockClient(api.handle)),
        ),
        tokenStoreProvider.overrideWithValue(
          MemoryTokenStore(api.signedIn ? 'tok' : null),
        ),
        todayProvider.overrideWithValue(testToday),
      ],
      child: const RinggitRunwayApp(),
    ),
  );
  await tester.pumpAndSettle();
}
