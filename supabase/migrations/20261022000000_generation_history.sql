-- NOVARYX-AI: per-user generation and chat history.
create table if not exists public.generation_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('chat', 'image', 'music', 'video')),
  prompt text not null,
  result_text text,
  result_url text,
  model text,
  created_at timestamptz not null default now()
);

create index if not exists generation_history_user_created_idx
  on public.generation_history (user_id, created_at desc);

alter table public.generation_history enable row level security;

drop policy if exists "Users can read their own generation history" on public.generation_history;
create policy "Users can read their own generation history"
  on public.generation_history for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their own generation history" on public.generation_history;
create policy "Users can insert their own generation history"
  on public.generation_history for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own generation history" on public.generation_history;
create policy "Users can delete their own generation history"
  on public.generation_history for delete
  to authenticated
  using (auth.uid() = user_id);

grant select, insert, delete on public.generation_history to authenticated;
