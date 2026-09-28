import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import 'src/api.dart';
import 'src/config.dart';
import 'src/http_util.dart';
import 'src/rate_limit.dart';

export 'src/config.dart' show Config, ConfigException;
export 'src/migrations.dart' show migrate;

/// The whole API as one shelf handler: CORS, JSON errors, rate limit on
/// /auth/*, then the routes.
Handler buildHandler(Config config, Pool db, {bool logRequests = false}) {
  var pipeline = const Pipeline();
  if (logRequests) pipeline = pipeline.addMiddleware(_logRequests());
  return pipeline
      .addMiddleware(corsMiddleware())
      .addMiddleware(errorMiddleware())
      .addMiddleware(
        rateLimit(
          perMinute: config.authRateLimitPerMinute,
          applies: (r) => r.url.path.startsWith('auth/'),
        ),
      )
      .addHandler(Api(db, config).router.call);
}

/// Logs method, path and status only: never query strings or bodies.
Middleware _logRequests() =>
    (inner) => (request) async {
      final watch = Stopwatch()..start();
      final response = await inner(request);
      print(
        '${DateTime.now().toIso8601String()} ${request.method} /${request.url.path} '
        '${response.statusCode} ${watch.elapsedMilliseconds}ms',
      );
      return response;
    };
