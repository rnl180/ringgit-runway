import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';

import 'http_util.dart';

class Auth {
  final String _secret;
  final int bcryptCost;
  final Duration tokenLifetime;

  /// Checked against when the email is unknown, so a login for a missing
  /// account takes as long as one with a wrong password.
  late final String _dummyHash = hashPassword('not-a-real-password');

  Auth(this._secret, {required this.bcryptCost, required this.tokenLifetime});

  String hashPassword(String password) =>
      BCrypt.hashpw(password, BCrypt.gensalt(logRounds: bcryptCost));

  bool checkPassword(String password, String? hash) {
    try {
      return BCrypt.checkpw(password, hash ?? _dummyHash) && hash != null;
    } catch (_) {
      return false;
    }
  }

  String issueToken(String userId) => JWT(
    {},
    subject: userId,
  ).sign(SecretKey(_secret), expiresIn: tokenLifetime);

  /// Returns the user id in a valid, unexpired HS256 token, or null.
  String? verifyToken(String token) {
    try {
      final header = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(token.split('.').first)),
        ),
      );
      if (header is! Map || header['alg'] != 'HS256') return null;
      final jwt = JWT.verify(token, SecretKey(_secret));
      final payload = jwt.payload;
      if (payload is! Map || payload['exp'] is! num) return null;
      final sub = jwt.subject;
      return (sub == null || sub.isEmpty) ? null : sub;
    } catch (_) {
      return null;
    }
  }

  /// Wraps a handler that needs a signed-in user.
  Handler authed(
    Future<Response> Function(Request request, String userId) handler,
  ) => (request) {
    final header = request.headers['authorization'] ?? '';
    if (!header.startsWith('Bearer ')) throw const ApiError.unauthorized();
    final userId = verifyToken(header.substring(7).trim());
    if (userId == null) throw const ApiError.unauthorized();
    return handler(request, userId);
  };
}
