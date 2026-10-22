create table if not exists public.community_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  description text not null default '' check (char_length(description) <= 500),
  kind text not null check (kind in ('image','video','music')),
  prompt text not null check (char_length(prompt) between 1 and 10000),
  style text not null default 'Cinematic',
  generation_mode text not null default '',
  aspect_ratio text not null default '16:9',
  result_url text,
  created_at timestamptz not null default now()
);

alter table public.community_templates enable row level security;

drop policy if exists "Anyone can view community templates" on public.community_templates;
create policy "Anyone can view community templates"
  on public.community_templates for select
  to authenticated
  using (true);

drop policy if exists "Users can post their own templates" on public.community_templates;
create policy "Users can post their own templates"
  on public.community_templates for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own templates" on public.community_templates;
create policy "Users can delete their own templates"
  on public.community_templates for delete
  to authenticated
  using (auth.uid() = user_id);

create index if not exists community_templates_created_at_idx
  on public.community_templates (created_at desc);
