-- Match each user's NOVARYX credits to the exact KIE credits consumed by successful tasks.
-- Missing user balances are initialized to 50; existing balances are preserved.
insert into public.generation_credits(user_id, balance)
select id, 50 from auth.users
on conflict (user_id) do nothing;

-- KIE's actual cost is reported after a task completes (recordInfo.creditsConsumed).
-- Negative balances represent a completed task whose actual KIE cost exceeded the
-- user's remaining balance; future generations are blocked until top-ups cover it.
alter table public.generation_credits
  drop constraint if exists generation_credits_balance_check;

create table if not exists public.kie_task_billing (
  task_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  generation_kind text not null check (generation_kind in ('image','video','music')),
  model text not null,
  status text not null default 'pending' check (status in ('pending','settled','failed')),
  credits_consumed integer,
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

create index if not exists kie_task_billing_user_created_idx
  on public.kie_task_billing(user_id, created_at desc);

alter table public.kie_task_billing enable row level security;
revoke all on public.kie_task_billing from anon, authenticated;
grant all on public.kie_task_billing to service_role;

create or replace function public.settle_kie_task_credits(p_task_id text, p_credits integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  task_row public.kie_task_billing%rowtype;
  new_balance integer;
begin
  if p_task_id is null or length(trim(p_task_id)) = 0 then
    raise exception 'Task ID is required';
  end if;
  if p_credits is null or p_credits < 0 then
    raise exception 'KIE reported an invalid credit amount';
  end if;

  select * into task_row
    from public.kie_task_billing
    where task_id = p_task_id
    for update;

  if not found then
    raise exception 'KIE task billing record not found';
  end if;

  if task_row.status = 'settled' then
    select balance into new_balance
      from public.generation_credits
      where user_id = task_row.user_id;
    return jsonb_build_object(
      'task_id', p_task_id,
      'credits_consumed', task_row.credits_consumed,
      'balance', new_balance,
      'already_settled', true
    );
  end if;

  if task_row.status = 'failed' then
    raise exception 'Failed KIE tasks cannot be billed';
  end if;

  insert into public.generation_credits(user_id, balance)
    values (task_row.user_id, 50)
    on conflict (user_id) do nothing;

  update public.generation_credits
    set balance = balance - p_credits, updated_at = now()
    where user_id = task_row.user_id
    returning balance into new_balance;

  update public.kie_task_billing
    set status = 'settled', credits_consumed = p_credits, settled_at = now()
    where task_id = p_task_id;

  return jsonb_build_object(
    'task_id', p_task_id,
    'credits_consumed', p_credits,
    'balance', new_balance,
    'already_settled', false
  );
end;
$$;

revoke all on function public.settle_kie_task_credits(text, integer) from public, anon, authenticated;
grant execute on function public.settle_kie_task_credits(text, integer) to service_role;
