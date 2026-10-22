-- Secure NOVARYX-AI credit purchases via Flutterwave.
create table if not exists public.credit_purchases (
  id uuid primary key default gen_random_uuid(),
  tx_ref text not null unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  credits integer not null check (credits in (100,250,500,1000,2500,5000,10000)),
  amount_ngn integer not null check (amount_ngn in (1332,3330,6659,13318,33295,66590,133180)),
  status text not null default 'pending' check (status in ('pending','verified','fulfilled','failed')),
  flutterwave_transaction_id text unique,
  created_at timestamptz not null default now(),
  fulfilled_at timestamptz
);
alter table public.credit_purchases enable row level security;
revoke all on public.credit_purchases from anon, authenticated;

create or replace function public.fulfill_credit_purchase(p_tx_ref text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare p public.credit_purchases%rowtype;
declare new_balance integer;
begin
  select * into p from public.credit_purchases where tx_ref = p_tx_ref for update;
  if not found then raise exception 'Purchase reference not found'; end if;
  if p.status = 'fulfilled' then
    select balance into new_balance from public.generation_credits where user_id = p.user_id;
    return jsonb_build_object('credits_added', p.credits, 'balance', new_balance, 'already_fulfilled', true);
  end if;
  if p.status <> 'verified' then raise exception 'Payment has not been verified'; end if;
  insert into public.generation_credits(user_id,balance) values(p.user_id,p.credits)
    on conflict(user_id) do update set balance = public.generation_credits.balance + excluded.balance, updated_at = now();
  update public.credit_purchases set status = 'fulfilled', fulfilled_at = now() where id = p.id;
  select balance into new_balance from public.generation_credits where user_id = p.user_id;
  return jsonb_build_object('credits_added', p.credits, 'balance', new_balance, 'already_fulfilled', false);
end;
$$;
revoke all on function public.fulfill_credit_purchase(text) from public, anon, authenticated;
grant execute on function public.fulfill_credit_purchase(text) to service_role;
