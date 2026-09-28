// Route tests against a real PostgreSQL database.
//
// Uses TEST_DATABASE_URL (default: the local ringgit_runway_test database).
// The test database's public schema is wiped and re-migrated on every run,
// so never point this at a database you care about.
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const _secret = 'test-secret-that-is-at-least-32-characters-long';

final _dbUrl =
    Platform.environment['TEST_DATABASE_URL'] ??
    'postgres://postgres:postgres@localhost:5432/ringgit_runway_test';

late Pool db;
late Handler app;

Config testConfig({int authRate = 1000}) => Config(
  databaseUrl: _dbUrl,
  jwtSecret: _secret,
  migrationsDir: '../db/migrations',
  bcryptCost: 4,
  authRateLimitPerMinute: authRate,
);

class Res {
  final int status;
  final dynamic body;
  final Map<String, String> headers;
  Res(this.status, this.body, this.headers);

  String? get errorCode => (body as Map?)?['error']?['code'] as String?;
  String? get errorMessage => (body as Map?)?['error']?['message'] as String?;
}

Future<Res> call(
  String method,
  String path, {
  Object? body,
  String? token,
  Handler? handler,
}) async {
  final response = await (handler ?? app)(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : (body is String ? body : jsonEncode(body)),
      headers: {
        if (token != null) 'authorization': 'Bearer $token',
        if (body != null) 'content-type': 'application/json',
      },
    ),
  );
  final text = await response.readAsString();
  return Res(
    response.statusCode,
    text.isEmpty ? null : jsonDecode(text),
    response.headers,
  );
}

var _n = 0;
Future<String> newUser([String? email]) async {
  final r = await call(
    'POST',
    '/auth/register',
    body: {
      'email': email ?? 'student${_n++}@example.com',
      'password': 'correct horse',
    },
  );
  expect(r.status, 201, reason: '${r.body}');
  return r.body['token'] as String;
}

void main() {
  setUpAll(() async {
    db = Pool.withUrl(_dbUrl);
    await db.execute(
      'drop schema public cascade; create schema public;',
      queryMode: QueryMode.simple,
    );
    final applied = await migrate(db, '../db/migrations');
    expect(
      applied,
      containsAllInOrder(['0001_init.sql', '0002_carry_over_once.sql']),
    );
    app = buildHandler(testConfig(), db);
  });

  tearDownAll(() => db.close());

  group('migrations', () {
    test('are recorded and not re-applied', () async {
      expect(await migrate(db, '../db/migrations'), isEmpty);
      final rows = await db.execute(
        'select version from schema_migrations order by version',
      );
      expect(rows.map((r) => r[0]), [
        '0001_init.sql',
        '0002_carry_over_once.sql',
      ]);
    });
  });

  group('basics', () {
    test('health', () async {
      final r = await call('GET', '/health');
      expect(r.status, 200);
      expect(r.body, {'ok': true});
    });

    test('unknown route is a JSON 404', () async {
      final r = await call('GET', '/nope');
      expect(r.status, 404);
      expect(r.errorCode, 'not_found');
    });

    test('CORS preflight', () async {
      final r = await call('OPTIONS', '/transactions');
      expect(r.status, 204);
      expect(r.headers['access-control-allow-origin'], '*');
    });

    test('config refuses the placeholder JWT secret', () {
      expect(
        () => Config(
          databaseUrl: _dbUrl,
          jwtSecret: 'change-me-to-a-long-random-string',
        ),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => Config(databaseUrl: _dbUrl, jwtSecret: 'short'),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('auth', () {
    test('register returns a token and the user', () async {
      final r = await call(
        'POST',
        '/auth/register',
        body: {
          'email': 'Aina@Example.com',
          'password': 'nasilemak123',
          'displayName': 'Aina',
        },
      );
      expect(r.status, 201);
      expect(r.body['token'], isA<String>());
      expect(r.body['user']['email'], 'Aina@Example.com');
      expect(r.body['user']['displayName'], 'Aina');
      expect(r.body['user']['monthlySavingsGoalSen'], 0);
      expect(r.body['user'].containsKey('password_hash'), isFalse);
    });

    test('email is unique regardless of case', () async {
      final r = await call(
        'POST',
        '/auth/register',
        body: {'email': 'aina@example.COM', 'password': 'nasilemak123'},
      );
      expect(r.status, 409);
      expect(r.errorCode, 'email_taken');
    });

    test('password is stored hashed', () async {
      final rows = await db.execute(
        Sql.named('select password_hash from users where lower(email) = @e'),
        parameters: {'e': 'aina@example.com'},
      );
      expect(rows.single[0], startsWith(r'$2'));
      expect(rows.single[0], isNot(contains('nasilemak123')));
    });

    test('register validation', () async {
      Future<Res> reg(Object body) =>
          call('POST', '/auth/register', body: body);
      expect(
        (await reg({'email': 'not-an-email', 'password': 'longenough'}))
            .errorMessage,
        contains('valid email'),
      );
      expect(
        (await reg({'email': 'a@b.co', 'password': 'short'})).errorMessage,
        'Password must be at least 8 characters.',
      );
      expect(
        (await reg({'email': 'a@b.co', 'password': 'x' * 73})).status,
        400,
      );
      expect(
        (await reg({'email': 'a@b.co'})).errorMessage,
        'Password is required.',
      );
      expect(
        (await reg({'password': 'longenough'})).errorMessage,
        'Email is required.',
      );
      final bad = await call('POST', '/auth/register', body: '{not json');
      expect(bad.status, 400);
      expect(bad.errorCode, 'bad_json');
    });

    test('login', () async {
      final ok = await call(
        'POST',
        '/auth/login',
        body: {'email': 'AINA@example.com', 'password': 'nasilemak123'},
      );
      expect(ok.status, 200);
      expect(ok.body['user']['displayName'], 'Aina');

      final wrong = await call(
        'POST',
        '/auth/login',
        body: {'email': 'aina@example.com', 'password': 'wrong-password'},
      );
      final unknown = await call(
        'POST',
        '/auth/login',
        body: {'email': 'nobody@example.com', 'password': 'whatever1'},
      );
      for (final r in [wrong, unknown]) {
        expect(r.status, 401);
        expect(r.errorCode, 'wrong_credentials');
        expect(r.errorMessage, 'Email or password is wrong.');
      }
    });

    test('protected routes need a valid token', () async {
      expect((await call('GET', '/me')).status, 401);
      expect((await call('GET', '/me', token: 'garbage')).status, 401);

      final token = await newUser();
      final sub = JWT.decode(token).subject!;
      final otherSecret = JWT({}, subject: sub).sign(
        SecretKey('a-different-secret-that-is-long-enough!!'),
        expiresIn: const Duration(hours: 1),
      );
      expect((await call('GET', '/me', token: otherSecret)).status, 401);

      final expired = JWT({
        'exp': 1,
      }, subject: sub).sign(SecretKey(_secret), noIssueAt: true);
      expect((await call('GET', '/me', token: expired)).status, 401);

      final noExp = JWT({}, subject: sub).sign(SecretKey(_secret));
      expect((await call('GET', '/me', token: noExp)).status, 401);

      String b64(Object o) =>
          base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      final none =
          '${b64({'alg': 'none', 'typ': 'JWT'})}.${b64({'sub': sub, 'exp': 9999999999})}.';
      expect((await call('GET', '/me', token: none)).status, 401);

      expect((await call('GET', '/me', token: token)).status, 200);
    });

    test('/auth is rate limited', () async {
      final limited = buildHandler(testConfig(authRate: 3), db);
      for (var i = 0; i < 3; i++) {
        final r = await call(
          'POST',
          '/auth/login',
          body: {'email': 'x@example.com', 'password': 'wrongwrong'},
          handler: limited,
        );
        expect(r.status, 401);
      }
      final r = await call(
        'POST',
        '/auth/login',
        body: {'email': 'x@example.com', 'password': 'wrongwrong'},
        handler: limited,
      );
      expect(r.status, 429);
      expect(r.errorCode, 'too_many_requests');
      expect(r.headers['retry-after'], isNotNull);
      // other routes are not limited
      expect((await call('GET', '/health', handler: limited)).status, 200);
    });
  });

  group('profile and categories', () {
    test('savings goal', () async {
      final t = await newUser();
      final r = await call(
        'PATCH',
        '/me',
        token: t,
        body: {'monthlySavingsGoalSen': 10000},
      );
      expect(r.status, 200);
      expect(r.body['user']['monthlySavingsGoalSen'], 10000);
      expect(
        (await call(
          'PATCH',
          '/me',
          token: t,
          body: {'monthlySavingsGoalSen': -1},
        )).errorMessage,
        "Savings goal can't be negative.",
      );
      expect(
        (await call(
          'PATCH',
          '/me',
          token: t,
          body: {'monthlySavingsGoalSen': 12.5},
        )).errorMessage,
        contains('whole sen'),
      );
      expect(
        (await call(
          'GET',
          '/me',
          token: t,
        )).body['user']['monthlySavingsGoalSen'],
        10000,
      );
    });

    test('categories', () async {
      final r = await call('GET', '/categories', token: await newUser());
      final cats = (r.body['categories'] as List).cast<Map>();
      expect(cats, hasLength(16));
      expect(cats.firstWhere((c) => c['id'] == 'food')['kind'], 'expense');
      expect(
        cats.firstWhere((c) => c['id'] == 'allowance')['label'],
        'Allowance',
      );
    });
  });

  group('transactions', () {
    late String t;
    setUpAll(() async => t = await newUser());

    Future<Res> add(Map<String, Object?> body) => call(
      'POST',
      '/transactions',
      token: t,
      body: {
        'kind': 'expense',
        'amountSen': 1250,
        'categoryId': 'food',
        'occurredOn': '2026-09-10',
        ...body,
      },
    );

    test('create and delete', () async {
      final r = await add({'note': '  Nasi lemak at the cafe  '});
      expect(r.status, 201);
      final tx = r.body['transaction'];
      expect(tx['amountSen'], 1250);
      expect(tx['note'], 'Nasi lemak at the cafe');
      expect(tx['occurredOn'], '2026-09-10');
      expect(tx['kind'], 'expense');

      expect(
        (await call('DELETE', '/transactions/${tx['id']}', token: t)).status,
        204,
      );
      expect(
        (await call('DELETE', '/transactions/${tx['id']}', token: t)).status,
        404,
      );
      expect(
        (await call('DELETE', '/transactions/not-a-uuid', token: t)).status,
        404,
      );
    });

    test('validation messages a student can act on', () async {
      expect(
        (await add({'amountSen': 0})).errorMessage,
        'Amount must be more than RM 0.',
      );
      expect(
        (await add({'amountSen': -5})).errorMessage,
        'Amount must be more than RM 0.',
      );
      expect(
        (await add({'amountSen': 12.5})).errorMessage,
        contains('whole sen'),
      );
      expect(
        (await add({'amountSen': '12'})).errorMessage,
        'Amount must be a number.',
      );
      expect(
        (await add({'amountSen': 100000001})).errorMessage,
        'Amount must be at most RM 1,000,000.00.',
      );
      expect(
        (await add({'kind': 'gift'})).errorMessage,
        contains('income or an expense'),
      );
      expect(
        (await add({'categoryId': 'allowance'})).errorMessage,
        contains('expense category'),
      );
      expect(
        (await add({'kind': 'income', 'categoryId': 'food'})).errorMessage,
        contains('income category'),
      );
      expect((await add({'categoryId': 'nope'})).status, 400);
      expect(
        (await add({'occurredOn': '2026-02-30'})).errorMessage,
        contains('real date'),
      );
      expect(
        (await add({'occurredOn': null})).errorMessage,
        'Date is required.',
      );
      expect((await add({'note': 'x' * 121})).errorMessage, contains('120'));
      expect((await add({'billId': 'abc'})).errorMessage, 'Bill is not valid.');
    });

    test('an empty note is stored as null', () async {
      final r = await add({'note': '   '});
      expect(r.body['transaction']['note'], isNull);
    });
  });

  group('a month with bills, limits and a summary', () {
    late String t;
    late String rentId, phoneId;

    setUpAll(() async {
      t = await newUser();
      await call(
        'PATCH',
        '/me',
        token: t,
        body: {'monthlySavingsGoalSen': 10000},
      );
      Future<String> bill(String name, int sen, int day, String cat) async {
        final r = await call(
          'POST',
          '/bills',
          token: t,
          body: {
            'name': name,
            'amountSen': sen,
            'dueDay': day,
            'categoryId': cat,
          },
        );
        expect(r.status, 201, reason: '${r.body}');
        return r.body['bill']['id'] as String;
      }

      rentId = await bill('Rent', 60000, 1, 'housing');
      phoneId = await bill('Phone plan', 3000, 15, 'phone');
      for (final e in [
        {
          'kind': 'income',
          'amountSen': 150000,
          'categoryId': 'allowance',
          'occurredOn': '2026-09-01',
        },
        {
          'kind': 'expense',
          'amountSen': 2000,
          'categoryId': 'food',
          'occurredOn': '2026-09-01',
        },
        {
          'kind': 'expense',
          'amountSen': 3000,
          'categoryId': 'food',
          'occurredOn': '2026-09-05',
        },
        {
          'kind': 'expense',
          'amountSen': 1500,
          'categoryId': 'food',
          'occurredOn': '2026-09-10',
        },
      ]) {
        expect(
          (await call('POST', '/transactions', token: t, body: e)).status,
          201,
        );
      }
      final pay = await call(
        'POST',
        '/bills/$rentId/pay',
        token: t,
        body: {'occurredOn': '2026-09-01'},
      );
      expect(pay.status, 201);
      expect(pay.body['transaction']['amountSen'], 60000);
      expect(pay.body['transaction']['billId'], rentId);
      expect(pay.body['transaction']['categoryId'], 'housing');
    });

    test('bill validation', () async {
      Future<Res> b(Map<String, Object?> body) => call(
        'POST',
        '/bills',
        token: t,
        body: {'name': 'Gym', 'amountSen': 5000, 'dueDay': 5, ...body},
      );
      expect(
        (await b({'dueDay': 32})).errorMessage,
        'Due day must be a whole number from 1 to 31.',
      );
      expect((await b({'name': ''})).errorMessage, 'Bill name is required.');
      expect((await b({'amountSen': 0})).status, 400);
      expect((await b({'categoryId': 'allowance'})).status, 400);
    });

    test('a bill can be paid only once a month', () async {
      final again = await call(
        'POST',
        '/bills/$rentId/pay',
        token: t,
        body: {'occurredOn': '2026-09-20'},
      );
      expect(again.status, 409);
      expect(again.errorMessage, 'Rent is already paid for September.');
      final direct = await call(
        'POST',
        '/transactions',
        token: t,
        body: {
          'kind': 'expense',
          'amountSen': 60000,
          'categoryId': 'housing',
          'occurredOn': '2026-09-02',
          'billId': rentId,
        },
      );
      expect(direct.status, 409);
      expect(direct.errorCode, 'bill_already_paid');
    });

    test('summary matches the budget math', () async {
      final r = await call(
        'GET',
        '/months/2026-09/summary?today=2026-09-10',
        token: t,
      );
      expect(r.status, 200);
      final s = r.body;
      expect(s['incomeSen'], 150000);
      expect(s['spentSen'], 66500);
      expect(s['unpaidBillsSen'], 3000);
      expect(s['leftSen'], 70500);
      expect(s['daysLeft'], 21);
      expect(s['spentTodaySen'], 1500);
      expect(s['dailyBudgetSen'], 3428);
      expect(s['safeTodaySen'], 1928);
      expect(s['poolSen'], 77000);
      expect(s['status'], 'onTrack');
      expect(s['statusMessage'], 'At this pace your money lasts the month.');
    });

    test('month view', () async {
      await call(
        'PUT',
        '/limits/food',
        token: t,
        body: {'monthlyLimitSen': 55000},
      );
      final r = await call('GET', '/months/2026-09?today=2026-09-10', token: t);
      expect(r.status, 200);
      final m = r.body;
      expect(m['month'], '2026-09');
      expect(m['savingsGoalSen'], 10000);
      expect((m['entries'] as List), hasLength(5));
      expect(
        m['entries'][0]['occurredOn'],
        '2026-09-10',
        reason: 'newest first',
      );
      final bills = (m['bills'] as List).cast<Map>();
      expect(bills.map((b) => b['name']), ['Rent', 'Phone plan']);
      expect(bills[0]['paidOn'], '2026-09-01');
      expect(bills[1]['paidOn'], isNull);
      expect(m['limits'], [
        {'categoryId': 'food', 'monthlyLimitSen': 55000},
      ]);
      expect(m['summary']['safeTodaySen'], 1928);
      expect(m['summary']['spentByCategorySen'], {
        'housing': 60000,
        'food': 6500,
      });
    });

    test('paying the phone bill leaves safe-to-spend unchanged', () async {
      final before = await call(
        'GET',
        '/months/2026-09/summary?today=2026-09-10',
        token: t,
      );
      final pay = await call(
        'POST',
        '/bills/$phoneId/pay?today=2026-09-10',
        token: t,
      );
      expect(pay.status, 201);
      expect(pay.body['transaction']['occurredOn'], '2026-09-10');
      final after = await call(
        'GET',
        '/months/2026-09/summary?today=2026-09-10',
        token: t,
      );
      expect(after.body['unpaidBillsSen'], 0);
      expect(after.body['safeTodaySen'], before.body['safeTodaySen']);
      expect(after.body['leftSen'], before.body['leftSen']);
    });

    test('limits', () async {
      expect(
        (await call(
          'PUT',
          '/limits/allowance',
          token: t,
          body: {'monthlyLimitSen': 100},
        )).status,
        400,
      );
      expect(
        (await call(
          'PUT',
          '/limits/food',
          token: t,
          body: {'monthlyLimitSen': 0},
        )).status,
        400,
      );
      expect((await call('DELETE', '/limits/food', token: t)).status, 204);
      final m = await call('GET', '/months/2026-09', token: t);
      expect(m.body['limits'], isEmpty);
    });

    test('editing and removing bills', () async {
      final r = await call(
        'PATCH',
        '/bills/$phoneId',
        token: t,
        body: {'amountSen': 3500},
      );
      expect(r.body['bill']['amountSen'], 3500);
      expect(
        (await call(
          'PATCH',
          '/bills/$phoneId',
          token: t,
          body: {'dueDay': 0},
        )).status,
        400,
      );

      expect((await call('DELETE', '/bills/$phoneId', token: t)).status, 204);
      final list = await call('GET', '/bills', token: t);
      expect((list.body['bills'] as List).map((b) => b['name']), ['Rent']);
      // Still shown in September because it was paid then.
      final sep = await call('GET', '/months/2026-09', token: t);
      expect(
        (sep.body['bills'] as List).map((b) => b['name']),
        contains('Phone plan'),
      );
      // Not reserved in October.
      final oct = await call(
        'GET',
        '/months/2026-10/summary?today=2026-10-01',
        token: t,
      );
      expect(oct.body['unpaidBillsSen'], 60000);
    });

    test('carry over', () async {
      // September left over: 150000 - 66500 - 3000 = 80500
      final r = await call('POST', '/months/2026-10/carry-over', token: t);
      expect(r.status, 201);
      expect(r.body['transaction']['amountSen'], 80500);
      expect(r.body['transaction']['categoryId'], 'carry_over');
      expect(r.body['transaction']['occurredOn'], '2026-10-01');
      expect(r.body['transaction']['note'], 'Left over from September');

      final again = await call('POST', '/months/2026-10/carry-over', token: t);
      expect(again.status, 409);
      expect(again.errorCode, 'already_carried');

      final m = await call('GET', '/months/2026-10?today=2026-10-01', token: t);
      expect(m.body['carryOver']['alreadyCarried'], isTrue);
      expect(m.body['carryOver']['previousLeftOverSen'], 80500);

      final nothing = await call(
        'POST',
        '/months/2026-12/carry-over',
        token: t,
      );
      expect(nothing.status, 422);
      expect(
        nothing.errorMessage,
        'Nothing left over from November to carry over.',
      );
    });

    test('bad month', () async {
      expect((await call('GET', '/months/2026-13', token: t)).status, 404);
      expect((await call('GET', '/months/sept', token: t)).status, 404);
      expect(
        (await call('GET', '/months/2026-09?today=yesterday', token: t)).status,
        400,
      );
    });
  });

  group('per-user scoping', () {
    test("one student can't see or touch another's data", () async {
      final a = await newUser();
      final b = await newUser();
      final tx = await call(
        'POST',
        '/transactions',
        token: a,
        body: {
          'kind': 'expense',
          'amountSen': 999,
          'categoryId': 'food',
          'occurredOn': '2026-09-03',
        },
      );
      final bill = await call(
        'POST',
        '/bills',
        token: a,
        body: {
          'name': 'Rent',
          'amountSen': 50000,
          'dueDay': 1,
          'categoryId': 'housing',
        },
      );
      final txId = tx.body['transaction']['id'];
      final billId = bill.body['bill']['id'];

      final bMonth = await call('GET', '/months/2026-09', token: b);
      expect(bMonth.body['entries'], isEmpty);
      expect(bMonth.body['bills'], isEmpty);
      expect((await call('GET', '/bills', token: b)).body['bills'], isEmpty);

      expect(
        (await call('DELETE', '/transactions/$txId', token: b)).status,
        404,
      );
      expect((await call('POST', '/bills/$billId/pay', token: b)).status, 404);
      expect(
        (await call(
          'PATCH',
          '/bills/$billId',
          token: b,
          body: {'amountSen': 1},
        )).status,
        404,
      );
      expect((await call('DELETE', '/bills/$billId', token: b)).status, 404);
      final steal = await call(
        'POST',
        '/transactions',
        token: b,
        body: {
          'kind': 'expense',
          'amountSen': 50000,
          'categoryId': 'housing',
          'occurredOn': '2026-09-03',
          'billId': billId,
        },
      );
      expect(steal.status, 404);

      // A's data is untouched.
      final aMonth = await call('GET', '/months/2026-09', token: a);
      expect(aMonth.body['entries'], hasLength(1));
      expect(
        (await call('GET', '/bills', token: a)).body['bills'][0]['amountSen'],
        50000,
      );
    });
  });
}
