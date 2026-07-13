-- ═══════════════════════════════════════════════════════
--  Recreate storage buckets on the new project
--  Run once in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════
--  The schema migration only covers the public schema — storage
--  buckets live in a separate subsystem and were never part of it.
--  Existing photo/video URLs in the database still point at the OLD
--  project and keep working regardless; this only unblocks NEW
--  uploads going forward on the new project.
--
--  All 5 are public buckets (read requires no auth, matching how
--  the app displays them directly via public URLs). Upload access
--  is "authenticated" broadly rather than admin-only, matching the
--  same relaxed pattern already used for the underlying public-schema
--  tables these buckets support (contestants, gallery_media, judges,
--  team_members) — the app gates who sees the upload UI, not the DB.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
    ('contestant-headshots', 'contestant-headshots', true, 10485760,
        array['image/jpeg','image/png','image/webp','image/heic','image/heif']),
    ('contestant-fullbody',  'contestant-fullbody',  true, 10485760,
        array['image/jpeg','image/png','image/webp','image/heic','image/heif']),
    ('contestant-videos',    'contestant-videos',    true, 209715200,
        array['video/mp4','video/quicktime','video/webm']),
    ('gallery-media',        'gallery-media',        true, 52428800,
        array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime']),
    ('people-photos',        'people-photos',        true, 10485760,
        array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do nothing;

drop policy if exists "Public read creme buckets" on storage.objects;
create policy "Public read creme buckets" on storage.objects
    for select
    using (bucket_id in ('contestant-headshots','contestant-fullbody','contestant-videos','gallery-media','people-photos'));

drop policy if exists "Authenticated manage creme buckets" on storage.objects;
create policy "Authenticated manage creme buckets" on storage.objects
    for all to authenticated
    using (bucket_id in ('contestant-headshots','contestant-fullbody','contestant-videos','gallery-media','people-photos'))
    with check (bucket_id in ('contestant-headshots','contestant-fullbody','contestant-videos','gallery-media','people-photos'));
