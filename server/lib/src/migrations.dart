import 'dart:io';

import 'package:postgres/postgres.dart';

/// Arbitrary constant so two servers starting at once don't both migrate.
const _lockKey = 7243901;

/// Applies every `*.sql` file in [dir] that is not yet recorded in
/// `schema_migrations`, in filename order, each in its own transaction.
/// Returns the versions applied.
Future<List<String>> migrate(Pool pool, String dir) async {
  final files =
      Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => _name(a).compareTo(_name(b)));
  if (files.isEmpty) {
    throw StateError('No migrations found in $dir');
  }

  return pool.withConnection((conn) async {
    await conn.execute('select pg_advisory_lock($_lockKey)');
    try {
      await conn.execute('''
        create table if not exists schema_migrations (
          version     text primary key,
          applied_at  timestamptz not null default now()
        )''');
      final done = (await conn.execute('select version from schema_migrations'))
          .map((r) => r[0] as String)
          .toSet();

      final applied = <String>[];
      for (final file in files) {
        final version = _name(file);
        if (done.contains(version)) continue;
        final sql = await file.readAsString();
        await conn.runTx((tx) async {
          await tx.execute(sql, queryMode: QueryMode.simple);
          await tx.execute(
            Sql.named('insert into schema_migrations (version) values (@v)'),
            parameters: {'v': version},
          );
        });
        applied.add(version);
      }
      return applied;
    } finally {
      await conn.execute('select pg_advisory_unlock($_lockKey)');
    }
  });
}

String _name(File f) => f.uri.pathSegments.last;
