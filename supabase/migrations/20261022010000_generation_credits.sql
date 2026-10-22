-- NOVARYX-AI generation credits. New accounts receive 50 starter credits.
create table if not exists public.generation_credits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance integer not null default 50 check (balance >= 0),
  updated_at timestamptz not null default now()
);

alter table public.generation_credits enable row level security;
drop policy if exists "Users can read their own credits" on public.generation_credits;
create policy "Users can read their own credits"
  on public.generation_credits for select to authenticated
  using (auth.uid() = user_id);
grant select on public.generation_credits to authenticated;

create or replace function public.initialize_generation_credits()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.generation_credits(user_id, balance)
  values (new.id, 50)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_generation_credits on auth.users;
create trigger on_auth_user_created_generation_credits
after insert on auth.users
for each row execute procedure public.initialize_generation_credits();

insert into public.generation_credits(user_id, balance)
select id, 50 from auth.users
on conflict (user_id) do nothing;

create or replace function public.spend_generation_credits(p_amount integer)
returns integer language plpgsql security definer set search_path = public
as $$
declare new_balance integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in to use generation credits';
  end if;
  if p_amount is null or p_amount < 1 or p_amount > 50 then
    raise exception 'Invalid credit amount';
  end if;
  update public.generation_credits
    set balance = balance - p_amount, updated_at = now()
    where user_id = auth.uid() and balance >= p_amount
    returning balance into new_balance;
  if new_balance is null then
    raise exception 'Not enough generation credits';
  end if;
  return new_balance;
end;
$$;

revoke all on function public.spend_generation_credits(integer) from public;
grant execute on function public.spend_generation_credits(integer) to authenticated;
