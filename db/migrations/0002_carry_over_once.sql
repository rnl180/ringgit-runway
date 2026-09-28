-- Last month's leftover can be carried into a month at most once.
create unique index transactions_carry_over_once_per_month
  on transactions (user_id, extract(year from occurred_on), extract(month from occurred_on))
  where category_id = 'carry_over';
