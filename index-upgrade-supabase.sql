-- Upgrade the existing WeChat messages table for replies, deletion, photos and voice messages.
-- Run this in Supabase SQL Editor after checking that public.messages is the table used by your current index.html.
-- This script does NOT delete existing messages.

alter table public.messages
  add column if not exists reply_to_id text,
  add column if not exists media_path text,
  add column if not exists media_type text,
  add column if not exists deleted_at timestamptz;


-- Allow an approved user to mark only their own messages as deleted.
-- RLS must be enabled for this policy to take effect.
alter table public.messages enable row level security;

drop policy if exists "couple messages update own" on public.messages;
create policy "couple messages update own"
on public.messages
for update
to authenticated
using (
  lower(coalesce(auth.jwt() ->> 'email', '')) in (
    'dinelesara@gmail.com',
    'webchat099@gmail.com'
  )
  and lower(coalesce(sender_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
)
with check (
  lower(coalesce(auth.jwt() ->> 'email', '')) in (
    'dinelesara@gmail.com',
    'webchat099@gmail.com'
  )
  and lower(coalesce(sender_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
);

-- Private bucket for image and voice uploads (not a public bucket).
insert into storage.buckets (id, name, public, file_size_limit)
values ('couple-media', 'couple-media', false, 12582912)
on conflict (id) do update
set public = false,
    file_size_limit = 12582912;

-- Remove only policies created by this migration, so it can safely be rerun.
drop policy if exists "couple media read for approved accounts" on storage.objects;
drop policy if exists "couple media upload to own folder" on storage.objects;
drop policy if exists "couple media delete from own folder" on storage.objects;

-- Both approved accounts can read files in this private bucket so they can see each other's media.
create policy "couple media read for approved accounts"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'couple-media'
  and lower(coalesce(auth.jwt() ->> 'email', '')) in (
    'dinelesara@gmail.com',
    'webchat099@gmail.com'
  )
);

-- Each approved account may upload only into its own auth-UUID folder.
create policy "couple media upload to own folder"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'couple-media'
  and lower(coalesce(auth.jwt() ->> 'email', '')) in (
    'dinelesara@gmail.com',
    'webchat099@gmail.com'
  )
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Each approved account may remove only its own uploaded media.
create policy "couple media delete from own folder"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'couple-media'
  and lower(coalesce(auth.jwt() ->> 'email', '')) in (
    'dinelesara@gmail.com',
    'webchat099@gmail.com'
  )
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- IMPORTANT:
-- Supabase RLS policies are combined permissively by default. Review existing policies
-- on public.messages and storage.objects to ensure no older broad policy grants access
-- to unauthorized users. Keep your existing message policies if they already restrict
-- access to the two intended accounts.
