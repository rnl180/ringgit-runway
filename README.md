# Ringgit Runway

Make your monthly allowance last the whole month.

Ringgit Runway is a student money tracker. Log what comes in and what goes out, set
aside your rent and phone bill, and it tells you how much you can safely spend **today**
so you don't run dry before the month ends.

Built with **Flutter** (app) and **PostgreSQL** (data), with a small Dart API in between.

## What it does

- **Safe to spend today:** your daily budget, recalculated every time you spend
- **Pace warning:** "At this pace your money runs out around 24 Sep"
- **Bills:** rent, phone plan and subscriptions are reserved before you see your spending money
- **Savings goal:** put some aside every month
- **Category limits:** e.g. Food & drinks RM 550
- **Charts:** daily spending against your budget line, spending by category
- **Carry over:** move last month's leftover into the new month

All amounts are in Malaysian Ringgit (RM).

## Project layout

```
app/      Flutter app (iOS, Android, web)
server/   Dart REST API (shelf + postgres)
db/       SQL migrations
```

## Run it locally

You need Flutter 3.x and PostgreSQL 16 or newer (or Docker).

```bash
docker compose up -d db          # or: createdb ringgit_runway
cp .env.example .env             # then set JWT_SECRET

cd server && dart pub get && dart run bin/server.dart
cd app && flutter pub get && flutter run -d chrome --dart-define=API_URL=http://localhost:8080
```

## Status

Early development. See [CLAUDE.md](CLAUDE.md) for the full spec.
