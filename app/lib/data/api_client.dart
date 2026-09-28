import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:runway_core/runway_core.dart';

import 'models.dart';

/// Base URL of the API. Set with `--dart-define=API_URL=http://...`.
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8080',
);

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  const ApiException(this.status, this.code, this.message);

  @override
  String toString() => message;
}

/// Thin typed wrapper over the REST API. Money stays in integer sen.
class ApiClient {
  final String baseUrl;
  final http.Client _http;
  String? token;

  /// Called when the server rejects the token, so the app can sign out.
  void Function()? onUnauthorized;

  ApiClient({this.baseUrl = apiUrl, http.Client? client, this.token})
    : _http = client ?? http.Client();

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri);
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const ApiException(
        0,
        'offline',
        "Can't reach Ringgit Runway. Check your connection and try again.",
      );
    }

    final text = response.body;
    final decoded = text.isEmpty ? null : _tryDecode(text);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final err = decoded is Map ? decoded['error'] : null;
    final code = err is Map
        ? (err['code'] as String? ?? 'error')
        : 'http_${response.statusCode}';
    final message = err is Map
        ? (err['message'] as String? ?? 'Something went wrong.')
        : 'Something went wrong (${response.statusCode}).';
    if (response.statusCode == 401 && token != null) onUnauthorized?.call();
    throw ApiException(response.statusCode, code, message);
  }

  static Object? _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  // auth

  Future<({String token, User user})> register(
    String email,
    String password,
    String? displayName,
  ) async {
    final j = await _send(
      'POST',
      '/auth/register',
      body: {
        'email': email,
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
      },
    ) as Map<String, dynamic>;
    return (
      token: j['token'] as String,
      user: User.fromJson(j['user'] as Map<String, dynamic>),
    );
  }

  Future<({String token, User user})> login(
    String email,
    String password,
  ) async {
    final j = await _send(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
    ) as Map<String, dynamic>;
    return (
      token: j['token'] as String,
      user: User.fromJson(j['user'] as Map<String, dynamic>),
    );
  }

  Future<User> me() async {
    final j = await _send('GET', '/me') as Map<String, dynamic>;
    return User.fromJson(j['user'] as Map<String, dynamic>);
  }

  Future<User> updateMe({
    String? displayName,
    int? monthlySavingsGoalSen,
  }) async {
    final j = await _send(
      'PATCH',
      '/me',
      body: {
        'displayName': ?displayName,
        'monthlySavingsGoalSen': ?monthlySavingsGoalSen,
      },
    ) as Map<String, dynamic>;
    return User.fromJson(j['user'] as Map<String, dynamic>);
  }

  // data

  Future<List<Category>> categories() async {
    final j = await _send('GET', '/categories') as Map<String, dynamic>;
    return [
      for (final c in j['categories'] as List)
        Category.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<MonthData> month(YearMonth m, LocalDate today) async {
    final j = await _send(
      'GET',
      '/months/$m',
      query: {'today': '$today'},
    ) as Map<String, dynamic>;
    return MonthData.fromJson(j);
  }

  Future<void> carryOver(YearMonth m) => _send('POST', '/months/$m/carry-over');

  Future<void> addEntry({
    required EntryKind kind,
    required int amountSen,
    required String categoryId,
    required LocalDate occurredOn,
    String? note,
  }) => _send(
    'POST',
    '/transactions',
    body: {
      'kind': kind.name,
      'amountSen': amountSen,
      'categoryId': categoryId,
      'occurredOn': '$occurredOn',
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    },
  );

  Future<void> deleteEntry(String id) => _send('DELETE', '/transactions/$id');

  Future<void> createBill({
    required String name,
    required int amountSen,
    required int dueDay,
    required String categoryId,
  }) => _send(
    'POST',
    '/bills',
    body: {
      'name': name,
      'amountSen': amountSen,
      'dueDay': dueDay,
      'categoryId': categoryId,
    },
  );

  Future<void> updateBill(
    String id, {
    String? name,
    int? amountSen,
    int? dueDay,
    String? categoryId,
  }) => _send(
    'PATCH',
    '/bills/$id',
    body: {
      'name': ?name,
      'amountSen': ?amountSen,
      'dueDay': ?dueDay,
      'categoryId': ?categoryId,
    },
  );

  Future<void> deleteBill(String id) => _send('DELETE', '/bills/$id');

  Future<void> payBill(String id, LocalDate on) =>
      _send('POST', '/bills/$id/pay', body: {'occurredOn': '$on'});

  Future<void> setLimit(String categoryId, int monthlyLimitSen) => _send(
    'PUT',
    '/limits/$categoryId',
    body: {'monthlyLimitSen': monthlyLimitSen},
  );

  Future<void> removeLimit(String categoryId) =>
      _send('DELETE', '/limits/$categoryId');
}
