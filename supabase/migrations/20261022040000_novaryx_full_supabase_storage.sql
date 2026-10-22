-- NOVARYX-AI: Supabase-first data and storage foundation
-- Apply after existing generation_credits and credit_purchases migrations.
-- Files live in private Storage buckets; Postgres stores metadata and ownership.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- User profile / preferences
CREATE TABLE IF NOT EXISTS public.user_profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  avatar_path TEXT,
  preferences JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Chat conversations
CREATE TABLE IF NOT EXISTS public.chat_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'New chat',
  model TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS chat_conversations_user_updated_idx
  ON public.chat_conversations(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user','assistant','system','tool')),
  content TEXT NOT NULL DEFAULT '',
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  model TEXT,
  token_usage JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS chat_messages_conversation_created_idx
  ON public.chat_messages(conversation_id, created_at);
CREATE INDEX IF NOT EXISTS chat_messages_user_created_idx
  ON public.chat_messages(user_id, created_at DESC);

-- AI outputs and user-uploaded files. file_path points to a private Storage bucket.
CREATE TABLE IF NOT EXISTS public.user_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  asset_type TEXT NOT NULL CHECK (asset_type IN ('upload','image','music','video','audio','document','other')),
  bucket_id TEXT NOT NULL DEFAULT 'user-assets',
  file_path TEXT NOT NULL,
  original_filename TEXT,
  mime_type TEXT,
  size_bytes BIGINT CHECK (size_bytes IS NULL OR size_bytes >= 0),
  prompt TEXT,
  provider TEXT,
  provider_job_id TEXT,
  status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('queued','processing','ready','failed','deleted')),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(bucket_id, file_path)
);
CREATE INDEX IF NOT EXISTS user_assets_user_created_idx
  ON public.user_assets(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS user_assets_user_type_idx
  ON public.user_assets(user_id, asset_type, created_at DESC);

-- Prompt templates shown in the app's template gallery.
CREATE TABLE IF NOT EXISTS public.prompt_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT 'general',
  media_type TEXT NOT NULL DEFAULT 'text' CHECK (media_type IN ('text','image','music','video')),
  prompt TEXT NOT NULL,
  preview_path TEXT,
  is_public BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS prompt_templates_public_category_idx
  ON public.prompt_templates(is_public, category, created_at DESC);

-- Generation job history; never store provider API secrets here.
CREATE TABLE IF NOT EXISTS public.generation_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  asset_id UUID REFERENCES public.user_assets(id) ON DELETE SET NULL,
  provider TEXT NOT NULL,
  media_type TEXT NOT NULL CHECK (media_type IN ('image','music','video','audio','text')),
  prompt TEXT NOT NULL,
  provider_job_id TEXT,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','processing','completed','failed','cancelled')),
  error_message TEXT,
  result_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS generation_jobs_user_created_idx
  ON public.generation_jobs(user_id, created_at DESC);

-- Keep updated_at current.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_profiles_set_updated_at ON public.user_profiles;
CREATE TRIGGER user_profiles_set_updated_at BEFORE UPDATE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS chat_conversations_set_updated_at ON public.chat_conversations;
CREATE TRIGGER chat_conversations_set_updated_at BEFORE UPDATE ON public.chat_conversations
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS user_assets_set_updated_at ON public.user_assets;
CREATE TRIGGER user_assets_set_updated_at BEFORE UPDATE ON public.user_assets
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS prompt_templates_set_updated_at ON public.prompt_templates;
CREATE TRIGGER prompt_templates_set_updated_at BEFORE UPDATE ON public.prompt_templates
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS generation_jobs_set_updated_at ON public.generation_jobs;
CREATE TRIGGER generation_jobs_set_updated_at BEFORE UPDATE ON public.generation_jobs
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Enable row-level security for all user data.
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generation_jobs ENABLE ROW LEVEL SECURITY;

-- Profiles: only the owner can read and edit their profile.
DROP POLICY IF EXISTS "profile_select_own" ON public.user_profiles;
CREATE POLICY "profile_select_own" ON public.user_profiles
FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "profile_insert_own" ON public.user_profiles;
CREATE POLICY "profile_insert_own" ON public.user_profiles
FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "profile_update_own" ON public.user_profiles;
CREATE POLICY "profile_update_own" ON public.user_profiles
FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Conversations: users can manage only their own.
DROP POLICY IF EXISTS "conversations_own_all" ON public.chat_conversations;
CREATE POLICY "conversations_own_all" ON public.chat_conversations
FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Messages: owner access, and conversation must belong to same user.
DROP POLICY IF EXISTS "messages_own_all" ON public.chat_messages;
CREATE POLICY "messages_own_all" ON public.chat_messages
FOR ALL TO authenticated
USING (
  auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.chat_conversations c
    WHERE c.id = conversation_id AND c.user_id = auth.uid()
  )
)
WITH CHECK (
  auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.chat_conversations c
    WHERE c.id = conversation_id AND c.user_id = auth.uid()
  )
);

-- Assets: owner access only.
DROP POLICY IF EXISTS "assets_own_all" ON public.user_assets;
CREATE POLICY "assets_own_all" ON public.user_assets
FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Templates: public templates readable by all signed-in users; private templates owner-only.
DROP POLICY IF EXISTS "templates_read_public_or_own" ON public.prompt_templates;
CREATE POLICY "templates_read_public_or_own" ON public.prompt_templates
FOR SELECT TO authenticated
USING (is_public = true OR owner_id = auth.uid());
DROP POLICY IF EXISTS "templates_insert_own" ON public.prompt_templates;
CREATE POLICY "templates_insert_own" ON public.prompt_templates
FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND is_public = false);
DROP POLICY IF EXISTS "templates_update_own" ON public.prompt_templates;
CREATE POLICY "templates_update_own" ON public.prompt_templates
FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
DROP POLICY IF EXISTS "templates_delete_own" ON public.prompt_templates;
CREATE POLICY "templates_delete_own" ON public.prompt_templates
FOR DELETE TO authenticated USING (owner_id = auth.uid());

-- Generation jobs: users may read their own jobs; server role should create/update jobs.
DROP POLICY IF EXISTS "generation_jobs_read_own" ON public.generation_jobs;
CREATE POLICY "generation_jobs_read_own" ON public.generation_jobs
FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Storage buckets are private. Use signed URLs for downloads.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('user-assets', 'user-assets', false, 524288000,
   ARRAY['image/jpeg','image/png','image/webp','image/gif','audio/mpeg','audio/mp4','audio/wav','audio/x-wav','video/mp4','video/webm','application/pdf','text/plain']),
  ('avatars', 'avatars', false, 10485760,
   ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage object paths must begin with the authenticated user's UUID.
DROP POLICY IF EXISTS "user_assets_storage_select_own" ON storage.objects;
CREATE POLICY "user_assets_storage_select_own" ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id IN ('user-assets','avatars') AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "user_assets_storage_insert_own" ON storage.objects;
CREATE POLICY "user_assets_storage_insert_own" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id IN ('user-assets','avatars') AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "user_assets_storage_update_own" ON storage.objects;
CREATE POLICY "user_assets_storage_update_own" ON storage.objects
FOR UPDATE TO authenticated
USING (bucket_id IN ('user-assets','avatars') AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id IN ('user-assets','avatars') AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "user_assets_storage_delete_own" ON storage.objects;
CREATE POLICY "user_assets_storage_delete_own" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id IN ('user-assets','avatars') AND (storage.foldername(name))[1] = auth.uid()::text);

-- Note: This migration does not move existing device-local files automatically.
-- The Flutter app must upload files to Storage and save metadata in user_assets.
-- Keep service-role and provider API keys only in Supabase Edge Function secrets.
