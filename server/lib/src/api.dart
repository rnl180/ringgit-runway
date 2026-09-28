import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:runway_core/runway_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'config.dart';
import 'http_util.dart';
import 'validate.dart';

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// The REST API. Every query that touches user data filters on the user id
/// from the verified token; ids in the URL are never trusted on their own.
class Api {
  final Pool db;
  final Config config;
  final Auth auth;

  Api(this.db, this.config)
    : auth = Auth(
        config.jwtSecret,
        bcryptCost: config.bcryptCost,
        tokenLifetime: config.tokenLifetime,
      );

  Router get router {
    final a = auth.authed;
    return Router(notFoundHandler: _notFound)
      ..get('/health', (Request _) => jsonOk({'ok': true}))
      ..post('/auth/register', _register)
      ..post('/auth/login', _login)
      ..get('/me', a(_getMe))
      ..patch('/me', a(_patchMe))
      ..get(
        '/categories',
        a((r, u) async => jsonOk({'categories': await _categories()})),
      )
      ..get('/months/<ym>', a(_getMonth))
      ..get('/months/<ym>/summary', a(_getSummary))
      ..post('/months/<ym>/carry-over', a(_carryOver))
      ..post('/transactions', a(_createTransaction))
      ..delete('/transactions/<id>', a(_deleteTransaction))
      ..get('/bills', a(_listBills))
      ..post('/bills', a(_createBill))
      ..patch('/bills/<id>', a(_updateBill))
      ..delete('/bills/<id>', a(_deleteBill))
      ..post('/bills/<id>/pay', a(_payBill))
      ..put('/limits/<categoryId>', a(_putLimit))
      ..delete('/limits/<categoryId>', a(_deleteLimit));
  }

  static Response _notFound(Request r) => errorResponse(
    404,
    'not_found',
    'No such endpoint: ${r.method} /${r.url.path}',
  );

  // ---------------------------------------------------------------- helpers

  Future<List<Map<String, dynamic>>> _q(
    String sql, [
    Map<String, Object?> params = const {},
    Session? session,
  ]) async {
    final result = await (session ?? db).execute(
      Sql.named(sql),
      parameters: params,
    );
    return [for (final row in result) row.toColumnMap()];
  }

  /// Today's date for this request: the app sends its local date as
  /// `?today=yyyy-mm-dd`; otherwise the server's time zone decides.
  LocalDate _today(Request r) {
    final param = r.url.queryParameters['today'];
    if (param != null) {
      return LocalDate.tryParse(param) ??
          (throw const ApiError.badRequest(
            'today must be a date like 2026-09-28.',
          ));
    }
    return LocalDate.fromDateTime(config.nowLocal());
  }

  static YearMonth _month(Request r) =>
      YearMonth.tryParse(r.params['ym']) ??
      (throw const ApiError.notFound('Months look like 2026-09.'));

  static String _id(Request r, String what) {
    final id = r.params['id'];
    if (!isUuid(id)) throw ApiError.notFound('That $what no longer exists.');
    return id!.toLowerCase();
  }

  Map<String, ({String kind, String label, int sortOrder})>? _categoryCache;

  Future<Map<String, ({String kind, String label, int sortOrder})>>
  _categoryMap() async => _categoryCache ??= {
    for (final c in await _q(
      'select id, kind::text as kind, label, sort_order from categories order by kind, sort_order',
    ))
      c['id'] as String: (
        kind: c['kind'] as String,
        label: c['label'] as String,
        sortOrder: c['sort_order'] as int,
      ),
  };

  Future<List<Map<String, Object?>>> _categories() async => [
    for (final e in (await _categoryMap()).entries)
      {
        'id': e.key,
        'kind': e.value.kind,
        'label': e.value.label,
        'sortOrder': e.value.sortOrder,
      },
  ];

  Future<void> _checkCategory(String? id, EntryKind kind) async {
    final c = (await _categoryMap())[id];
    if (c == null || c.kind != kind.name) {
      throw ApiError.badRequest(
        kind == EntryKind.income
            ? 'Pick an income category, like Allowance.'
            : 'Pick an expense category, like Food & drinks.',
      );
    }
  }

  static Map<String, Object?> _userJson(Map<String, dynamic> u) => {
    'id': u['id'],
    'email': u['email'],
    'displayName': u['display_name'],
    'currency': u['currency'],
    'monthlySavingsGoalSen': u['monthly_savings_goal_sen'],
    'createdAt': (u['created_at'] as DateTime).toUtc().toIso8601String(),
  };

  static const _userCols =
      'id, email, display_name, currency, monthly_savings_goal_sen, created_at';

  static const _txCols =
      'id, kind::text as kind, amount_sen, category_id, note, '
      'occurred_on::text as occurred_on, bill_id, created_at';

  static Map<String, Object?> _txJson(Map<String, dynamic> t) => {
    'id': t['id'],
    'kind': t['kind'],
    'amountSen': t['amount_sen'],
    'categoryId': t['category_id'],
    'note': t['note'],
    'occurredOn': t['occurred_on'],
    'billId': t['bill_id'],
    'createdAt': (t['created_at'] as DateTime).toUtc().toIso8601String(),
  };

  static const _billCols = 'id, name, amount_sen, due_day, category_id, active';

  static Map<String, Object?> _billJson(Map<String, dynamic> b) => {
    'id': b['id'],
    'name': b['name'],
    'amountSen': b['amount_sen'],
    'dueDay': b['due_day'],
    'categoryId': b['category_id'],
    'active': b['active'],
  };

  static bool _isUniqueViolation(Object e) =>
      e is ServerException && e.code == '23505';

  // ------------------------------------------------------------------- auth

  Future<Response> _register(Request r) async {
    final body = await readJson(r);
    final f = Fields(body);
    final email = f.requiredString('email', label: 'Email', maxLength: 254);
    if (!_email.hasMatch(email)) {
      throw const ApiError.badRequest(
        'Enter a valid email address, like you@example.com.',
      );
    }
    final password = _password(body['password']);
    final displayName = f.optionalString(
      'displayName',
      label: 'Name',
      maxLength: 40,
    );

    try {
      final rows = await _q(
        'insert into users (email, password_hash, display_name) '
        'values (@e, @h, @n) returning $_userCols',
        {'e': email, 'h': auth.hashPassword(password), 'n': displayName},
      );
      final user = rows.single;
      return jsonOk({
        'token': auth.issueToken(user['id'] as String),
        'user': _userJson(user),
      }, status: 201);
    } catch (e) {
      if (_isUniqueViolation(e)) {
        throw const ApiError.conflict(
          'email_taken',
          'That email already has an account. Sign in instead.',
        );
      }
      rethrow;
    }
  }

  /// Passwords are not trimmed. bcrypt only reads the first 72 bytes.
  static String _password(Object? v) {
    if (v is! String || v.isEmpty) {
      throw const ApiError.badRequest('Password is required.');
    }
    if (v.length < 8) {
      throw const ApiError.badRequest(
        'Password must be at least 8 characters.',
      );
    }
    if (utf8.encode(v).length > 72) {
      throw const ApiError.badRequest(
        'Password must be at most 72 characters.',
      );
    }
    return v;
  }

  Future<Response> _login(Request r) async {
    final body = await readJson(r);
    final email = body['email'], password = body['password'];
    if (email is! String ||
        password is! String ||
        email.isEmpty ||
        password.isEmpty) {
      throw const ApiError.badRequest('Enter your email and password.');
    }
    final rows = await _q(
      'select $_userCols, password_hash from users where lower(email) = lower(@e)',
      {'e': email.trim()},
    );
    final user = rows.isEmpty ? null : rows.single;
    if (!auth.checkPassword(password, user?['password_hash'] as String?)) {
      throw const ApiError(
        401,
        'wrong_credentials',
        'Email or password is wrong.',
      );
    }
    return jsonOk({
      'token': auth.issueToken(user!['id'] as String),
      'user': _userJson(user),
    });
  }

  // --------------------------------------------------------------------- me

  Future<Map<String, dynamic>> _user(String userId) async {
    final rows = await _q('select $_userCols from users where id = @u', {
      'u': userId,
    });
    if (rows.isEmpty) throw const ApiError.unauthorized();
    return rows.single;
  }

  Future<Response> _getMe(Request r, String userId) async =>
      jsonOk({'user': _userJson(await _user(userId))});

  Future<Response> _patchMe(Request r, String userId) async {
    final f = Fields(await readJson(r));
    final sets = <String>[];
    final params = <String, Object?>{'u': userId};
    if (f.has('displayName')) {
      sets.add('display_name = @n');
      params['n'] = f.optionalString(
        'displayName',
        label: 'Name',
        maxLength: 40,
      );
    }
    if (f.has('monthlySavingsGoalSen')) {
      sets.add('monthly_savings_goal_sen = @g');
      params['g'] = f.amountSen(
        'monthlySavingsGoalSen',
        label: 'Savings goal',
        allowZero: true,
      );
    }
    if (sets.isEmpty) return _getMe(r, userId);
    final rows = await _q(
      'update users set ${sets.join(', ')} where id = @u returning $_userCols',
      params,
    );
    if (rows.isEmpty) throw const ApiError.unauthorized();
    return jsonOk({'user': _userJson(rows.single)});
  }

  // ----------------------------------------------------------------- months

  Future<
    ({
      List<Map<String, dynamic>> entries,
      List<Map<String, dynamic>> bills,
      List<Map<String, dynamic>> limits,
      int savingsGoalSen,
      int previousLeftOverSen,
    })
  >
  _loadMonth(String userId, YearMonth m) async {
    final range = {
      'u': userId,
      'from': m.first.toString(),
      'to': m.last.toString(),
    };
    final prev = m.previous;
    final results = await Future.wait([
      _q(
        'select $_txCols from transactions where user_id = @u '
        'and occurred_on between @from::date and @to::date '
        'order by occurred_on desc, created_at desc',
        range,
      ),
      _q(
        'select b.id, b.name, b.amount_sen, b.due_day, b.category_id, b.active, '
        't.id as paid_transaction_id, t.occurred_on::text as paid_on, '
        't.amount_sen as paid_amount_sen '
        'from bills b left join transactions t on t.bill_id = b.id '
        'and t.occurred_on between @from::date and @to::date '
        'where b.user_id = @u and (b.active or t.id is not null) '
        'order by b.due_day, b.name',
        range,
      ),
      _q(
        'select category_id, monthly_limit_sen from category_limits where user_id = @u '
        'order by category_id',
        {'u': userId},
      ),
      _q('select monthly_savings_goal_sen from users where id = @u', {
        'u': userId,
      }),
      _q(
        "select coalesce(sum(case when kind = 'income' then amount_sen "
        'else -amount_sen end), 0)::bigint as left_over from transactions '
        'where user_id = @u and occurred_on between @from::date and @to::date',
        {
          'u': userId,
          'from': prev.first.toString(),
          'to': prev.last.toString(),
        },
      ),
    ]);
    if (results[3].isEmpty) throw const ApiError.unauthorized();
    return (
      entries: results[0],
      bills: results[1],
      limits: results[2],
      savingsGoalSen: results[3].single['monthly_savings_goal_sen'] as int,
      previousLeftOverSen: results[4].single['left_over'] as int,
    );
  }

  static MonthSummary _summarize(
    YearMonth month,
    LocalDate today,
    ({
      List<Map<String, dynamic>> entries,
      List<Map<String, dynamic>> bills,
      List<Map<String, dynamic>> limits,
      int savingsGoalSen,
      int previousLeftOverSen,
    })
    data,
  ) => summarizeMonth(
    month: month,
    today: today,
    entries: [
      for (final t in data.entries)
        BudgetEntry(
          kind: EntryKind.tryParse(t['kind'] as String)!,
          amountSen: t['amount_sen'] as int,
          occurredOn: LocalDate.tryParse(t['occurred_on'] as String)!,
          categoryId: t['category_id'] as String,
          billId: t['bill_id'] as String?,
        ),
    ],
    bills: [
      for (final b in data.bills)
        BudgetBill(
          id: b['id'] as String,
          amountSen: b['amount_sen'] as int,
          active: b['active'] as bool,
        ),
    ],
    savingsGoalSen: data.savingsGoalSen,
  );

  Future<Response> _getMonth(Request r, String userId) async {
    final month = _month(r);
    final today = _today(r);
    final data = await _loadMonth(userId, month);
    final carried = data.entries.any((t) => t['category_id'] == 'carry_over');
    return jsonOk({
      'month': month.toString(),
      'today': today.toString(),
      'savingsGoalSen': data.savingsGoalSen,
      'entries': data.entries.map(_txJson).toList(),
      'bills': [
        for (final b in data.bills)
          {
            ..._billJson(b),
            'paidTransactionId': b['paid_transaction_id'],
            'paidOn': b['paid_on'],
            'paidAmountSen': b['paid_amount_sen'],
          },
      ],
      'limits': [
        for (final l in data.limits)
          {
            'categoryId': l['category_id'],
            'monthlyLimitSen': l['monthly_limit_sen'],
          },
      ],
      'carryOver': {
        'fromMonth': month.previous.toString(),
        'previousLeftOverSen': data.previousLeftOverSen,
        'alreadyCarried': carried,
      },
      'summary': _summarize(month, today, data).toJson(),
    });
  }

  Future<Response> _getSummary(Request r, String userId) async {
    final month = _month(r);
    final summary = _summarize(
      month,
      _today(r),
      await _loadMonth(userId, month),
    );
    return jsonOk({
      ...summary.toJson(),
      'statusMessage': statusMessage(summary),
    });
  }

  Future<Response> _carryOver(Request r, String userId) async {
    final month = _month(r);
    final data = await _loadMonth(userId, month);
    final from = month.previous;
    final fromName = monthLongNames[from.month - 1];
    if (data.previousLeftOverSen <= 0) {
      throw ApiError(
        422,
        'nothing_to_carry',
        'Nothing left over from $fromName to carry over.',
      );
    }
    try {
      final rows = await _q(
        "insert into transactions (user_id, kind, amount_sen, category_id, note, occurred_on) "
        "values (@u, 'income', @a, 'carry_over', @n, @d::date) returning $_txCols",
        {
          'u': userId,
          'a': data.previousLeftOverSen,
          'n': 'Left over from $fromName',
          'd': month.first.toString(),
        },
      );
      return jsonOk({'transaction': _txJson(rows.single)}, status: 201);
    } catch (e) {
      if (_isUniqueViolation(e)) {
        throw ApiError.conflict(
          'already_carried',
          "$fromName's leftover is already carried into this month.",
        );
      }
      rethrow;
    }
  }

  // ----------------------------------------------------------- transactions

  Future<Response> _createTransaction(Request r, String userId) async {
    final f = Fields(await readJson(r));
    final kind = f.kind('kind');
    final amount = f.amountSen('amountSen');
    final categoryId = f.requiredString(
      'categoryId',
      label: 'Category',
      maxLength: 40,
    );
    await _checkCategory(categoryId, kind);
    final note = f.optionalString('note', label: 'Note', maxLength: 120);
    final occurredOn = f.requiredDate('occurredOn');
    final billId = f.optionalUuid('billId', label: 'Bill');

    if (billId != null) {
      if (kind != EntryKind.expense) {
        throw const ApiError.badRequest('Only expenses can pay a bill.');
      }
      final owned = await _q(
        'select 1 from bills where id = @b and user_id = @u',
        {'b': billId, 'u': userId},
      );
      if (owned.isEmpty) {
        throw const ApiError.notFound('That bill no longer exists.');
      }
    }

    try {
      final rows = await _q(
        'insert into transactions (user_id, kind, amount_sen, category_id, note, occurred_on, bill_id) '
        'values (@u, @k::entry_kind, @a, @c, @n, @d::date, @b::uuid) returning $_txCols',
        {
          'u': userId,
          'k': kind.name,
          'a': amount,
          'c': categoryId,
          'n': note,
          'd': occurredOn.toString(),
          'b': billId,
        },
      );
      return jsonOk({'transaction': _txJson(rows.single)}, status: 201);
    } catch (e) {
      if (_isUniqueViolation(e)) {
        throw billId != null
            ? const ApiError.conflict(
                'bill_already_paid',
                'That bill is already paid this month.',
              )
            : const ApiError.conflict(
                'already_carried',
                'Last month is already carried into this month.',
              );
      }
      rethrow;
    }
  }

  Future<Response> _deleteTransaction(Request r, String userId) async {
    final id = _id(r, 'entry');
    final rows = await _q(
      'delete from transactions where id = @id and user_id = @u returning id',
      {'id': id, 'u': userId},
    );
    if (rows.isEmpty) {
      throw const ApiError.notFound('That entry no longer exists.');
    }
    return Response(204);
  }

  // ------------------------------------------------------------------ bills

  Future<Response> _listBills(Request r, String userId) async {
    final rows = await _q(
      'select $_billCols from bills where user_id = @u and active order by due_day, name',
      {'u': userId},
    );
    return jsonOk({'bills': rows.map(_billJson).toList()});
  }

  Future<Response> _createBill(Request r, String userId) async {
    final f = Fields(await readJson(r));
    final name = f.requiredString('name', label: 'Bill name', maxLength: 60);
    final amount = f.amountSen('amountSen');
    final dueDay = f.intInRange('dueDay', label: 'Due day', min: 1, max: 31);
    final categoryId =
        f.optionalString('categoryId', label: 'Category', maxLength: 40) ??
        'other_out';
    await _checkCategory(categoryId, EntryKind.expense);
    final rows = await _q(
      'insert into bills (user_id, name, amount_sen, due_day, category_id) '
      'values (@u, @n, @a, @d, @c) returning $_billCols',
      {'u': userId, 'n': name, 'a': amount, 'd': dueDay, 'c': categoryId},
    );
    return jsonOk({'bill': _billJson(rows.single)}, status: 201);
  }

  Future<Response> _updateBill(Request r, String userId) async {
    final id = _id(r, 'bill');
    final f = Fields(await readJson(r));
    final sets = <String>[];
    final params = <String, Object?>{'id': id, 'u': userId};
    if (f.has('name')) {
      sets.add('name = @n');
      params['n'] = f.requiredString('name', label: 'Bill name', maxLength: 60);
    }
    if (f.has('amountSen')) {
      sets.add('amount_sen = @a');
      params['a'] = f.amountSen('amountSen');
    }
    if (f.has('dueDay')) {
      sets.add('due_day = @d');
      params['d'] = f.intInRange('dueDay', label: 'Due day', min: 1, max: 31);
    }
    if (f.has('categoryId')) {
      final c = f.requiredString(
        'categoryId',
        label: 'Category',
        maxLength: 40,
      );
      await _checkCategory(c, EntryKind.expense);
      sets.add('category_id = @c');
      params['c'] = c;
    }
    final rows = await _q(
      sets.isEmpty
          ? 'select $_billCols from bills where id = @id and user_id = @u and active'
          : 'update bills set ${sets.join(', ')} where id = @id and user_id = @u and active '
                'returning $_billCols',
      params,
    );
    if (rows.isEmpty) {
      throw const ApiError.notFound('That bill no longer exists.');
    }
    return jsonOk({'bill': _billJson(rows.single)});
  }

  /// Bills are deactivated rather than deleted so past payments keep their name.
  Future<Response> _deleteBill(Request r, String userId) async {
    final id = _id(r, 'bill');
    final rows = await _q(
      'update bills set active = false where id = @id and user_id = @u and active returning id',
      {'id': id, 'u': userId},
    );
    if (rows.isEmpty) {
      throw const ApiError.notFound('That bill no longer exists.');
    }
    return Response(204);
  }

  Future<Response> _payBill(Request r, String userId) async {
    final id = _id(r, 'bill');
    final f = Fields(await readJson(r));
    final on = f.optionalDate('occurredOn') ?? _today(r);
    final bills = await _q(
      'select $_billCols from bills where id = @id and user_id = @u and active',
      {'id': id, 'u': userId},
    );
    if (bills.isEmpty) {
      throw const ApiError.notFound('That bill no longer exists.');
    }
    final bill = bills.single;
    try {
      final rows = await _q(
        "insert into transactions (user_id, kind, amount_sen, category_id, note, occurred_on, bill_id) "
        "values (@u, 'expense', @a, @c, @n, @d::date, @b) returning $_txCols",
        {
          'u': userId,
          'a': bill['amount_sen'],
          'c': bill['category_id'],
          'n': bill['name'],
          'd': on.toString(),
          'b': id,
        },
      );
      return jsonOk({'transaction': _txJson(rows.single)}, status: 201);
    } catch (e) {
      if (_isUniqueViolation(e)) {
        throw ApiError.conflict(
          'bill_already_paid',
          '${bill['name']} is already paid for ${monthLongNames[on.month - 1]}.',
        );
      }
      rethrow;
    }
  }

  // ----------------------------------------------------------------- limits

  Future<Response> _putLimit(Request r, String userId) async {
    final categoryId = r.params['categoryId'];
    await _checkCategory(categoryId, EntryKind.expense);
    final limit = Fields(await readJson(r))
        .amountSen('monthlyLimitSen', label: 'Limit');
    await _q(
      'insert into category_limits (user_id, category_id, monthly_limit_sen) values (@u, @c, @l) '
      'on conflict (user_id, category_id) do update set monthly_limit_sen = excluded.monthly_limit_sen',
      {'u': userId, 'c': categoryId, 'l': limit},
    );
    return jsonOk({
      'limit': {'categoryId': categoryId, 'monthlyLimitSen': limit},
    });
  }

  Future<Response> _deleteLimit(Request r, String userId) async {
    await _q(
      'delete from category_limits where user_id = @u and category_id = @c',
      {'u': userId, 'c': r.params['categoryId']},
    );
    return Response(204);
  }
}
