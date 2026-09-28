import 'dart:convert';

import 'package:shelf/shelf.dart';

/// An error the client can act on, sent as `{error: {code, message}}`.
class ApiError implements Exception {
  final int status;
  final String code;
  final String message;

  const ApiError(this.status, this.code, this.message);

  const ApiError.badRequest(this.message, {this.code = 'invalid_input'})
    : status = 400;
  const ApiError.notFound(this.message) : status = 404, code = 'not_found';
  const ApiError.conflict(this.code, this.message) : status = 409;
  const ApiError.unauthorized([this.message = 'Please sign in again.'])
    : status = 401,
      code = 'unauthorized';

  @override
  String toString() => 'ApiError($status $code: $message)';
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Response jsonOk(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: _jsonHeaders);

Response errorResponse(
  int status,
  String code,
  String message, {
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: jsonEncode({
    'error': {'code': code, 'message': message},
  }),
  headers: {..._jsonHeaders, ...headers},
);

/// Turns thrown [ApiError]s into JSON and hides everything else behind a
/// generic 500 (logged, never sent to the client).
Middleware errorMiddleware() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on ApiError catch (e) {
        return errorResponse(e.status, e.code, e.message);
      } catch (e, st) {
        print(
          'Unhandled error on ${request.method} ${request.requestedUri.path}: $e\n$st',
        );
        return errorResponse(
          500,
          'server_error',
          'Something went wrong on our side. Try again.',
        );
      }
    };

/// Allows the Flutter web app (served from another port or host) to call
/// the API. Auth is by bearer token, not cookies, so any origin is fine.
Middleware corsMiddleware() {
  const headers = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-max-age': '86400',
  };
  return (inner) => (request) async {
    if (request.method == 'OPTIONS') return Response(204, headers: headers);
    final response = await inner(request);
    return response.change(headers: headers);
  };
}

/// Reads a JSON object body. An empty body is an empty object.
Future<Map<String, Object?>> readJson(Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // fall through
  }
  throw const ApiError.badRequest(
    'Request body must be a JSON object.',
    code: 'bad_json',
  );
}
