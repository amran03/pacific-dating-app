-- ============================================================
-- PROFILE PHOTOS (multi-photo, max 6) — Pacific Dating App
-- ============================================================
-- Mtumiaji anaweza kuweka hadi picha 6 kwenye profile yake. Picha ya
-- position 0 ni YA MBELE (inayotumika kwenye cards, chat list, nk).
--
-- Storage:
--   Bucket `profile-photos` (public read). Path: {user_id}/{uuid}.jpg
--   RLS: INSERT/UPDATE/DELETE kwa mmiliki tu (folder la user id yake).
--
-- Table:
--   profile_photos (id, user_id, url, position 0-5, created_at)
--   Limit ya 6 inalindwa na TRIGGER kwenye DB (si app tu).
--
-- Endesha SQL hii yote kwenye Supabase Dashboard > SQL Editor.

-- 1) Bucket ya picha za profile (public read).
insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', true)
on conflict (id) do nothing;

-- 2) Storage policies — mmiliki tu anaandika kwenye folder lake.
drop policy if exists "profile-photos public read" on storage.objects;
create policy "profile-photos public read"
  on storage.objects for select
  using (bucket_id = 'profile-photos');

drop policy if exists "profile-photos own insert" on storage.objects;
create policy "profile-photos own insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = cast(auth.uid() as text)
  );

drop policy if exists "profile-photos own update" on storage.objects;
create policy "profile-photos own update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = cast(auth.uid() as text)
  );

drop policy if exists "profile-photos own delete" on storage.objects;
create policy "profile-photos own delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = cast(auth.uid() as text)
  );

-- 3) Table ya metadata ya picha.
create table if not exists public.profile_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(uid) on delete cascade,
  url text not null,
  position int not null default 0 check (position >= 0 and position <= 5),
  created_at timestamptz not null default now()
);

create index if not exists profile_photos_user_idx
  on public.profile_photos(user_id, position);

alter table public.profile_photos enable row level security;

-- 4) RLS — SELECT kwa watu walioweka (waone picha zote); write kwa mmiliki.
drop policy if exists "profile_photos select" on public.profile_photos;
create policy "profile_photos select"
  on public.profile_photos for select
  to authenticated
  using (true);

drop policy if exists "profile_photos insert own" on public.profile_photos;
create policy "profile_photos insert own"
  on public.profile_photos for insert to authenticated
  with check (cast(user_id as text) = cast(auth.uid() as text));

drop policy if exists "profile_photos update own" on public.profile_photos;
create policy "profile_photos update own"
  on public.profile_photos for update to authenticated
  using (cast(user_id as text) = cast(auth.uid() as text))
  with check (cast(user_id as text) = cast(auth.uid() as text));

drop policy if exists "profile_photos delete own" on public.profile_photos;
create policy "profile_photos delete own"
  on public.profile_photos for delete to authenticated
  using (cast(user_id as text) = cast(auth.uid() as text));

-- 5) LIMIT YA 6 — trigger inayokataa picha ya saba (DB-level, si app tu).
create or replace function public.enforce_profile_photo_limit()
returns trigger
language plpgsql
as $$
declare
  photo_count int;
begin
  if (tg_op = 'INSERT') then
    select count(*) into photo_count
      from public.profile_photos
      where user_id = new.user_id;
    if photo_count >= 6 then
      raise exception 'PROFILE_PHOTO_LIMIT: umefika kikomo cha picha 6';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profile_photos_limit_trigger on public.profile_photos;
create trigger profile_photos_limit_trigger
  before insert on public.profile_photos
  for each row execute function public.enforce_profile_photo_limit();

-- 6) MIGRATION — picha ya sasa (users.profile_image_url) iingie kama
--    position 0 kwa watumiaji wote walio na picha tayari.
insert into public.profile_photos (user_id, url, position)
select uid, profile_image_url, 0
from public.users
where profile_image_url is not null
  and profile_image_url <> ''
on conflict do nothing;
