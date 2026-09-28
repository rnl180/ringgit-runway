import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart';

Future<void> main(List<String> args) async {
  final Config config;
  try {
    config = Config.fromEnvironment();
  } on ConfigException catch (e) {
    stderr.writeln('Config error: $e');
    exit(64);
  }

  final db = Pool.withUrl(config.databaseUrl);
  try {
    final applied = await migrate(db, config.migrationsDir);
    print(
      applied.isEmpty
          ? 'Database schema is up to date.'
          : 'Applied migrations: ${applied.join(', ')}',
    );
  } catch (e) {
    stderr.writeln('Could not prepare the database: $e');
    stderr.writeln('Is PostgreSQL running and DATABASE_URL correct?');
    exit(69);
  }

  final server = await serve(
    buildHandler(config, db, logRequests: true),
    InternetAddress.anyIPv4,
    config.port,
  );
  print('Ringgit Runway API listening on http://localhost:${server.port}');

  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    await db.close();
    exit(0);
  });
}
