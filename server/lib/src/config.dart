import 'dart:io';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _placeholderSecret = 'change-me-to-a-long-random-string';

/// Server settings, read from environment variables (and a local `.env`
/// file if there is one; real environment variables win).
class Config {
  final String databaseUrl;
  final String jwtSecret;
  final int port;
  final String timeZone;
  final String migrationsDir;
  final int bcryptCost;

  /// Requests allowed per client per minute on /auth/*.
  final int authRateLimitPerMinute;

  final Duration tokenLifetime;

  Config({
    required this.databaseUrl,
    required this.jwtSecret,
    this.port = 8080,
    this.timeZone = 'Asia/Kuala_Lumpur',
    String? migrationsDir,
    this.bcryptCost = 10,
    this.authRateLimitPerMinute = 10,
    this.tokenLifetime = const Duration(days: 30),
  }) : migrationsDir = migrationsDir ?? findMigrationsDir() {
    if (jwtSecret.length < 32 || jwtSecret == _placeholderSecret) {
      throw ConfigException(
        'JWT_SECRET must be a random string of at least 32 characters. '
        'Generate one with: openssl rand -hex 32',
      );
    }
    _location(timeZone); // fail fast on a bad TZ name
  }

  factory Config.fromEnvironment() {
    final env = {..._readDotEnv(), ...Platform.environment};
    String need(String key) {
      final v = env[key];
      if (v == null || v.isEmpty) {
        throw ConfigException(
          '$key is not set. Copy .env.example to .env and fill it in.',
        );
      }
      return v;
    }

    return Config(
      databaseUrl: need('DATABASE_URL'),
      jwtSecret: need('JWT_SECRET'),
      port: int.tryParse(env['PORT'] ?? '') ?? 8080,
      timeZone: (env['TZ'] ?? '').isEmpty ? 'Asia/Kuala_Lumpur' : env['TZ']!,
      migrationsDir: env['MIGRATIONS_DIR'],
      bcryptCost: int.tryParse(env['BCRYPT_COST'] ?? '') ?? 10,
      authRateLimitPerMinute:
          int.tryParse(env['AUTH_RATE_LIMIT_PER_MINUTE'] ?? '') ?? 10,
    );
  }

  /// Today's calendar date in the server's configured time zone.
  DateTime nowLocal() => tz.TZDateTime.now(_location(timeZone));
}

var _tzLoaded = false;

tz.Location _location(String name) {
  if (!_tzLoaded) {
    tzdata.initializeTimeZones();
    _tzLoaded = true;
  }
  try {
    return tz.getLocation(name);
  } on tz.LocationNotFoundException {
    throw ConfigException(
      'TZ "$name" is not a known time zone, e.g. Asia/Kuala_Lumpur',
    );
  }
}

class ConfigException implements Exception {
  final String message;
  ConfigException(this.message);
  @override
  String toString() => message;
}

/// `db/migrations` lives at the repo root; the server may be started from
/// the repo root or from `server/`.
String findMigrationsDir() {
  for (final candidate in ['db/migrations', '../db/migrations']) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  return 'db/migrations';
}

Map<String, String> _readDotEnv() {
  for (final path in ['.env', '../.env']) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final out = <String, String>{};
    for (final raw in f.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      out[line.substring(0, eq).trim()] = value;
    }
    return out;
  }
  return const {};
}
