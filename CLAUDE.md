# Ringgit Runway

A money tracker for a university student in Malaysia (Taylor's University, Subang Jaya).
The one job: **make this month's money last until the end of the month.** Every screen
should answer "how much can I still spend today?" before anything else.

Currency is Malaysian Ringgit, shown as `RM 1,234.50`.

## Layout

```
app/      Flutter app (iOS, Android, web)
server/   Dart REST API (shelf) talking to PostgreSQL
db/       SQL migrations, applied in filename order
```

The app never talks to PostgreSQL directly. It calls the API; only the server holds
database credentials.

## Stack

- **App:** Flutter, Riverpod for state, go_router for navigation, `http` or dio for the
  API, fl_chart for charts, flutter_secure_storage for the auth token.
- **Server:** Dart, `shelf` + `shelf_router`, `postgres` package (v3), bcrypt password
  hashing, JWT access tokens. Config from environment variables (see `.env.example`).
- **Database:** PostgreSQL 16+ (developed against 18). Schema in `db/migrations/`.
  Add new migrations as new numbered files; never edit an applied one. The server applies
  pending migrations at startup and records them in a `schema_migrations` table.

## Money rules

- Store and compute money as integer **sen** (`amount_sen`, RM 1.00 = 100). Never use
  `double` for money anywhere, including JSON (send integers).
- Format only at the UI edge.
- A month is a calendar month in the user's local date (`Asia/Kuala_Lumpur` by default).

## Budget math (the core feature)

Put this in pure Dart with no Flutter or database imports, with thorough unit tests,
so both the server's summary endpoint and the app can use it. For the viewed month:

| Term | Definition |
|---|---|
| income | sum of income entries this month |
| spent | sum of expense entries this month (includes paid bills) |
| unpaidBills | sum of active bills not yet paid this month |
| savingsGoal | user's monthly savings goal |
| left | income − spent − unpaidBills − savingsGoal |
| daysLeft | days from today to month end, **including today** |
| spentToday | expenses dated today, excluding bill payments |
| dailyBudget | (left + spentToday) / daysLeft — today's budget as it stood this morning |
| safeToday | dailyBudget − spentToday — the hero number |
| pool | income − totalBills − savingsGoal (money for day-to-day spending) |
| discretionarySpent | spent − paid bill amounts |
| runOutDay | if average daily discretionary spend so far would empty `pool` before month end, the day it happens |

Status, shown as a labelled pill (never color alone):
- **Over budget** if `left < 0`
- **Spending fast** if `runOutDay` falls before the last day of the month ("At this pace
  your money runs out around 24 Sep")
- **On track** otherwise
- **No income yet** when income is 0; prompt to add allowance or last month's leftover.

If `safeToday` is negative, say how far over today's budget they are and what tomorrow's
daily budget becomes: `left / (daysLeft − 1)`.

Past months show "Left over" (income − spent) instead of daily numbers.

## Screens

1. **Home (this month).** Hero card with "Safe to spend today", daily budget, days left
   and money left after bills and savings. Status pill. A runway bar comparing % of the
   month gone against % of the spending pool used. Small stats: income, spent, bills
   still due, saving.
2. **Add entry.** Expense/Income toggle, large amount field with `RM` prefix, category
   chips, optional note (placeholder like "Nasi lemak at the cafe"), date (defaults to
   today). Must be fast: open, type amount, tap category, save.
3. **Activity.** Entries grouped by day, income in green with `+`, swipe or tap to
   delete with an in-app confirmation.
4. **Insights.** Daily spending bar chart for the month (bill payments excluded) with a
   dashed line at `pool / daysInMonth`; bars above the line in the warning color.
   Spending by category with each category's limit when one is set.
5. **Bills & plan.** Fixed bills (name, amount, due day, category) with Paid / Due in N
   days / Overdue state and a "Mark paid" action that creates the expense entry. Monthly
   savings goal. Per-category limits.
6. **Month switcher** to browse earlier months. "Carry over" action on a new month that
   adds last month's leftover as a `carry_over` income entry.
7. **Sign up / sign in** with email + password.

First run should not be an empty shell: walk the user through entering their monthly
allowance and main bills (rent, phone plan) so the home screen has real numbers.

## API sketch

All routes except auth need `Authorization: Bearer <token>`; every query is scoped to
the token's user id.

```
POST   /auth/register          {email, password, displayName?}
POST   /auth/login             {email, password} -> {token, user}
GET    /me                     profile + savings goal
PATCH  /me                     {displayName?, monthlySavingsGoalSen?}
GET    /categories
GET    /months/{yyyy-mm}       entries + bills with paid state + limits
GET    /months/{yyyy-mm}/summary   the budget math above
POST   /transactions           {kind, amountSen, categoryId, note?, occurredOn, billId?}
DELETE /transactions/{id}
GET|POST /bills, PATCH|DELETE /bills/{id}
POST   /bills/{id}/pay         {occurredOn?} -> creates the expense entry
PUT    /limits/{categoryId}    {monthlyLimitSen} ; DELETE to remove
```

Validate every input on the server. Return JSON errors as `{error: {code, message}}`
with messages a student can act on ("Amount must be more than RM 0").

## Security

- This repository is **public**. Never commit `.env`, real credentials, tokens or
  personal financial data. Only `.env.example` with placeholder values.
- Hash passwords with bcrypt. Keep JWT secret in env. Parameterized SQL only.
- Rate-limit `/auth/*`.

## Local development

```bash
# database (Postgres.app, Homebrew or docker compose up -d db)
createdb ringgit_runway
cp .env.example .env    # then edit

cd server && dart pub get && dart run bin/server.dart
cd app && flutter pub get && flutter run -d chrome --dart-define=API_URL=http://localhost:8080
```

## Done means

- `dart test` passes in `server/` (budget math + route tests against a real test database).
- `flutter analyze` is clean and `flutter test` passes in `app/`.
- README explains setup in a few steps.
