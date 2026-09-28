-- Ringgit Runway: initial schema.
-- Money is stored as integer sen (RM 1.00 = 100) so sums never drift.

create type entry_kind as enum ('income', 'expense');

create table users (
  id                        uuid primary key default gen_random_uuid(),
  email                     text not null,
  password_hash             text not null,
  display_name              text,
  currency                  char(3) not null default 'MYR',
  monthly_savings_goal_sen  bigint not null default 0 check (monthly_savings_goal_sen >= 0),
  created_at                timestamptz not null default now()
);
create unique index users_email_lower_key on users (lower(email));

create table categories (
  id          text primary key,
  kind        entry_kind not null,
  label       text not null,
  sort_order  int not null,
  unique (id, kind)
);

insert into categories (id, kind, label, sort_order) values
  ('food',        'expense', 'Food & drinks',      10),
  ('groceries',   'expense', 'Groceries',          20),
  ('transport',   'expense', 'Transport',          30),
  ('housing',     'expense', 'Rent & utilities',   40),
  ('phone',       'expense', 'Phone & internet',   50),
  ('study',       'expense', 'Study & books',      60),
  ('fun',         'expense', 'Fun & going out',    70),
  ('shopping',    'expense', 'Shopping',           80),
  ('health',      'expense', 'Health',             90),
  ('other_out',   'expense', 'Other',             100),
  ('allowance',   'income',  'Allowance',          10),
  ('job',         'income',  'Part-time job',      20),
  ('scholarship', 'income',  'Scholarship / loan', 30),
  ('gift',        'income',  'Gift',               40),
  ('carry_over',  'income',  'Carried over',       50),
  ('other_in',    'income',  'Other',              60);

-- Fixed monthly bills (rent, phone plan, subscriptions). Unpaid bills are
-- reserved out of the month's spending money until they are marked paid.
create table bills (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users (id) on delete cascade,
  name         text not null check (length(name) between 1 and 60),
  amount_sen   bigint not null check (amount_sen > 0),
  due_day      smallint not null check (due_day between 1 and 31),
  category_id  text not null,
  kind         entry_kind not null default 'expense' check (kind = 'expense'),
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  foreign key (category_id, kind) references categories (id, kind)
);
create index bills_user_idx on bills (user_id) where active;

create table transactions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users (id) on delete cascade,
  kind         entry_kind not null,
  amount_sen   bigint not null check (amount_sen > 0),
  category_id  text not null,
  note         text check (note is null or length(note) <= 120),
  occurred_on  date not null,
  bill_id      uuid references bills (id) on delete set null,
  created_at   timestamptz not null default now(),
  -- the category must match the entry kind (no "Allowance" expenses)
  foreign key (category_id, kind) references categories (id, kind),
  check (bill_id is null or kind = 'expense')
);
create index transactions_user_month_idx on transactions (user_id, occurred_on);
-- a bill can be paid at most once per calendar month
create unique index transactions_bill_once_per_month
  on transactions (bill_id, extract(year from occurred_on), extract(month from occurred_on))
  where bill_id is not null;

-- Optional monthly cap per expense category ("Food: RM 550").
create table category_limits (
  user_id            uuid not null references users (id) on delete cascade,
  category_id        text not null,
  kind               entry_kind not null default 'expense' check (kind = 'expense'),
  monthly_limit_sen  bigint not null check (monthly_limit_sen > 0),
  primary key (user_id, category_id),
  foreign key (category_id, kind) references categories (id, kind)
);
