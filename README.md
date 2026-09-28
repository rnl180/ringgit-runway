# Ringgit Runway

Make your monthly allowance last the whole month.

Ringgit Runway is a student money tracker. Log what comes in and what goes out, set
aside your rent and phone bill, and it tells you how much you can safely spend **today**
so you don't run dry before the month ends.

Built with **Flutter** (app) and **PostgreSQL** (data), with a small Dart API in between.

## What it does

- **Safe to spend today:** your daily budget, recalculated every time you spend
- **Pace warning:** "At this pace your money runs out around 24 Sep"
- **Bills:** rent, phone plan and subscriptions are set aside before you see your
  spending money, with Paid / Due in N days / Overdue and a one-tap "Mark paid"
- **Savings goal:** put some aside every month
- **Category limits:** e.g. Food & drinks RM 550, with an over-limit warning
- **Charts:** daily spending against your daily line, spending by category
- **Carry over:** move last month's leftover into the new month
- **First run:** enter your allowance, rent and phone plan and the home screen has real
  numbers straight away

All amounts are in Malaysian Ringgit (RM) and stored as whole sen, so totals never drift.

## Project layout

```
app/                   Flutter app (Android, iOS, web)
server/                Dart REST API (shelf + postgres)
packages/runway_core/  Budget math shared by the app and the server (pure Dart)
db/migrations/         SQL migrations, applied by the server at startup
```

## Run it locally

You need [Flutter](https://docs.flutter.dev/get-started/install) 3.x (it includes Dart)
and PostgreSQL 16 or newer, or Docker for the database.

**1. Database**

```bash
docker compose up -d db        # or, with a local PostgreSQL: createdb ringgit_runway
```

**2. Settings.** Copy the example file and put a random secret in it:

```bash
cp .env.example .env
openssl rand -hex 32           # paste the output as JWT_SECRET in .env
```

`.env` is ignored by git. Never commit it.

**3. API** (creates the tables on first start)

```bash
cd server
dart pub get
dart run bin/server.dart       # http://localhost:8080
```

**4. App**, in a second terminal

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:8080
```

Create an account, enter your allowance and bills, and you're in.

## Run it on your phone

Your phone and laptop must be on the same Wi-Fi. Find your laptop's Wi-Fi address
(macOS: `ipconfig getifaddr en0`, Windows: `ipconfig`), for example `192.168.1.23`.
The API from step 3 already listens on every network interface.

**Android:** turn on Developer options and USB debugging, plug the phone in, then

```bash
cd app
flutter devices                                   # find your phone's id
flutter run -d <phone-id> --dart-define=API_URL=http://192.168.1.23:8080
```

**iPhone:** needs a Mac with Xcode. Open `app/ios/Runner.xcworkspace` once to pick your
Apple ID under Signing & Capabilities, then run the same `flutter run` command. Allow
"Local Network" access when iOS asks.

**Any phone, no cable:** build the web version and open it in the phone's browser:

```bash
cd app
flutter build web --dart-define=API_URL=http://192.168.1.23:8080
cd build/web && python3 -m http.server 8081       # open http://192.168.1.23:8081
```

Over plain http on Wi-Fi the web version forgets your sign-in when you close the tab;
the installed Android and iOS apps remember it.

Debug builds may use plain `http://` to your laptop. To publish the app you need the API
on a server with `https://`.

## Tests

```bash
cd packages/runway_core && dart test   # budget math
createdb ringgit_runway_test           # once (Docker: docker compose exec db createdb -U postgres ringgit_runway_test)
cd server && dart test                 # API routes against a real PostgreSQL database
cd app && flutter analyze && flutter test
```

The test database is wiped and rebuilt on every run. The server tests use `TEST_DATABASE_URL`, defaulting to
`postgres://postgres:postgres@localhost:5432/ringgit_runway_test`.

See [CLAUDE.md](CLAUDE.md) for the full spec and API.
