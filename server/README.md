# Ringgit Runway API

Dart REST API (shelf + PostgreSQL). See the root [README](../README.md) for setup
and [CLAUDE.md](../CLAUDE.md) for the routes.

```bash
dart pub get
dart run bin/server.dart   # reads ../.env, applies pending migrations, listens on PORT
dart test                  # needs the ringgit_runway_test database (wiped on every run)
```

Environment variables: `DATABASE_URL`, `JWT_SECRET` (32+ random characters),
`PORT` (default 8080), `TZ` (default `Asia/Kuala_Lumpur`), and optionally
`TEST_DATABASE_URL`, `MIGRATIONS_DIR`, `BCRYPT_COST`, `AUTH_RATE_LIMIT_PER_MINUTE`.
