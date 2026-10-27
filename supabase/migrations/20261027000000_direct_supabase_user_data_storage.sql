-- NOVARYX-AI: core user-owned data tables and private file storage.
-- Safe to apply repeatedly; existing tables and bucket settings are preserved.

create table if not exists public.chat_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'NOVARYX Chat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists chat_conversations_user_updated_idx
  on public.chat_conversations(user_id, updated_at desc);
alter table public.chat_conversations enable row level security;
drop policy if exists "Users manage their own chat conversations" on public.chat_conversations;
create policy "Users manage their own chat conversations"
  on public.chat_conversations for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update, delete on public.chat_conversations to authenticated;

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.chat_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  model text,
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_conversation_created_idx
  on public.chat_messages(conversation_id, created_at);
create index if not exists chat_messages_user_created_idx
  on public.chat_messages(user_id, created_at desc);
alter table public.chat_messages enable row level security;
drop policy if exists "Users manage their own chat messages" on public.chat_messages;
create policy "Users manage their own chat messages"
  on public.chat_messages for all to authenticated
  using (
    auth.uid() = user_id
    and exists (
      select 1 from public.chat_conversations c
      where c.id = conversation_id and c.user_id = auth.uid()
    )
  )
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.chat_conversations c
      where c.id = conversation_id and c.user_id = auth.uid()
    )
  );
grant select, insert, update, delete on public.chat_messages to authenticated;

create table if not exists public.user_assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  asset_type text not null default 'other',
  bucket_id text not null default 'user-assets',
  file_path text not null,
  original_filename text,
  mime_type text,
  size_bytes bigint,
  prompt text,
  provider text,
  provider_job_id text,
  status text not null default 'ready',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists user_assets_user_created_idx
  on public.user_assets(user_id, created_at desc);
alter table public.user_assets enable row level security;
drop policy if exists "Users manage their own assets" on public.user_assets;
create policy "Users manage their own assets"
  on public.user_assets for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update, delete on public.user_assets to authenticated;

-- Keep uploaded/generated files private; paths must start with the owner's auth UID.
insert into storage.buckets (id, name, public)
values ('user-assets', 'user-assets', false)
on conflict (id) do update set public = false;

drop policy if exists "Users read their own stored assets" on storage.objects;
create policy "Users read their own stored assets"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'user-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
drop policy if exists "Users upload their own stored assets" on storage.objects;
create policy "Users upload their own stored assets"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'user-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
drop policy if exists "Users update their own stored assets" on storage.objects;
create policy "Users update their own stored assets"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'user-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'user-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
drop policy if exists "Users delete their own stored assets" on storage.objects;
create policy "Users delete their own stored assets"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'user-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
