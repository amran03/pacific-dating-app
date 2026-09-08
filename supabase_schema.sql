-- ============================================================
-- PACIFIC DATING APP — Supabase schema
-- Run this ONCE in: Supabase Dashboard > SQL Editor > New query
-- ============================================================

-- ---------- USERS ----------
create table if not exists public.users (
  uid uuid primary key references auth.users (id) on delete cascade,
  name text not null default '',
  name_lower text not null default '',
  age int not null default 0,
  birth_date text,
  gender text,
  bio text,
  interested_gender text,
  relationship_goal text,
  profile_image_url text,
  phone_number text,
  auth_email text,
  location text,
  latitude double precision,
  longitude double precision,
  fcm_token text,
  coins int not null default 0,
  badge_tier text not null default 'none',
  total_spent_coins int not null default 0,
  height_cm int,
  education text,
  occupation text,
  interests text[] default '{}',
  smoking_habit text,
  drinking_habit text,
  chat_unlock_price int not null default 0,
  location_enabled boolean not null default false,
  notifications_enabled boolean not null default true,
  is_online boolean not null default false,
  last_seen text,
  is_profile_complete boolean not null default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ---------- SWIPES ----------
create table if not exists public.swipes (
  from_uid uuid not null references auth.users (id) on delete cascade,
  target_uid uuid not null references auth.users (id) on delete cascade,
  action text not null check (action in ('like', 'pass')),
  created_at timestamptz default now(),
  primary key (from_uid, target_uid)
);

-- ---------- MATCHES ----------
create table if not exists public.matches (
  id text primary key,
  user_a uuid not null,
  user_b uuid not null,
  matched_at timestamptz default now()
);

-- ---------- CHAT ROOMS ----------
create table if not exists public.chat_rooms (
  id text primary key,
  participants uuid[] not null default '{}',
  unlocked_by uuid[] not null default '{}',
  last_message text not null default '',
  last_message_at text not null default '',
  typing uuid,
  created_at timestamptz default now()
);

-- ---------- MESSAGES ----------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id text not null,
  sender_id uuid not null,
  receiver_id uuid not null,
  content text not null default '',
  type text not null default 'text', -- text | image | audio
  media_url text,
  seen boolean not null default false,
  created_at timestamptz default now()
);

-- ---------- NOTIFICATIONS ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  to_uid uuid not null references auth.users (id) on delete cascade,
  type text not null default 'message', -- match | message | gift | coins
  title text not null default '',
  description text not null default '',
  read boolean not null default false,
  created_at timestamptz default now()
);

-- ---------- GIFTS ----------
create table if not exists public.gifts (
  id text primary key,
  name text not null,
  emoji text,
  image_url text,
  coin_price int not null default 0,
  tier text not null default 'basic',
  glow_color text
);

-- Idempotently add columns in case the table exists from an earlier run.
do $$
begin
  if not exists (select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'gifts' and column_name = 'tier') then
    alter table public.gifts add column tier text not null default 'basic';
  end if;
  if not exists (select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'gifts' and column_name = 'glow_color') then
    alter table public.gifts add column glow_color text;
  end if;
end $$;

-- Seed the gift catalogue (matches the app's pasificGifts list).
-- Emojis use E'...' unicode escapes on purpose: plain emoji chars can get
-- corrupted when copy-pasting the file on Windows editors. PostgreSQL escape
-- strings require \uXXXX (4 hex) or \UXXXXXXXX (8 hex) — exactly as written.
insert into public.gifts (id, name, emoji, coin_price, tier, glow_color) values
  ('g1', 'Rose',         E'\U0001F339',  10,  'basic',   '0xFFFF4B6E'),
  ('g2', 'Coffee',       E'\u2615',      20,  'basic',   '0xFFB07B4F'),
  ('g3', 'Chocolate',    E'\U0001F36B',  35,  'premium', '0xFF8B5A2B'),
  ('g4', 'Teddy Bear',   E'\U0001F9F8',  50,  'premium', '0xFFE8A857'),
  ('g5', 'Perfume',      E'\U0001F338',  75,  'premium', '0xFFC77DFF'),
  ('g6', 'Crown',        E'\U0001F451', 100,  'luxury',  '0xFFFFB800'),
  ('g7', 'Diamond Ring', E'\U0001F48E', 200,  'luxury',  '0xFF66D9FF'),
  ('g8', 'Sports Car',   E'\U0001F3CE\uFE0F', 350, 'luxury', '0xFFFF5252'),
  ('g9', 'Island',       E'\U0001F3DD\uFE0F', 500, 'luxury', '0xFF00C9A7')
on conflict (id) do nothing;

-- ---------- COIN PURCHASES ----------
create table if not exists public.coin_purchases (
  id uuid primary key default gen_random_uuid(),
  uid uuid not null references auth.users (id) on delete cascade,
  coins int not null default 0,
  amount numeric not null default 0,
  created_at timestamptz default now()
);


-- ============================================================
-- REALTIME (needed for live chat, presence, likes, notifications)
-- Only adds each table if it isn't already a member, so the script
-- stays safe to re-run.
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['users', 'swipes', 'chat_rooms', 'messages', 'notifications'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ============================================================
-- ROW LEVEL SECURITY — every signed-in user can only touch
-- their own rows / conversations they participate in.
-- ============================================================
alter table public.users enable row level security;
alter table public.swipes enable row level security;
alter table public.matches enable row level security;
alter table public.chat_rooms enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;
alter table public.gifts enable row level security;
alter table public.coin_purchases enable row level security;

-- USERS
drop policy if exists "users readable by authenticated" on public.users;
create policy "users readable by authenticated" on public.users
  for select to authenticated using (true);
drop policy if exists "users self insert" on public.users;
create policy "users self insert" on public.users
  for insert to authenticated with check (uid = auth.uid());
drop policy if exists "users self update" on public.users;
create policy "users self update" on public.users
  for update to authenticated using (uid = auth.uid());
drop policy if exists "users self delete" on public.users;
create policy "users self delete" on public.users
  for delete to authenticated using (uid = auth.uid());

-- SWIPES
drop policy if exists "swipes self all" on public.swipes;
create policy "swipes self all" on public.swipes
  for all to authenticated using (from_uid = auth.uid())
  with check (from_uid = auth.uid());

-- MATCHES (both participants)
drop policy if exists "matches participants" on public.matches;
create policy "matches participants" on public.matches
  for all to authenticated
  using (user_a = auth.uid() or user_b = auth.uid())
  with check (user_a = auth.uid() or user_b = auth.uid());

-- CHAT ROOMS (both participants)
drop policy if exists "chat rooms participants" on public.chat_rooms;
create policy "chat rooms participants" on public.chat_rooms
  for all to authenticated
  using (auth.uid() = any (participants))
  with check (auth.uid() = any (participants));

-- MESSAGES (sender or receiver)
drop policy if exists "messages participants" on public.messages;
create policy "messages participants" on public.messages
  for all to authenticated
  using (sender_id = auth.uid() or receiver_id = auth.uid())
  with check (sender_id = auth.uid() or receiver_id = auth.uid());

-- NOTIFICATIONS (recipient can read/update, anyone signed-in can send)
drop policy if exists "notifications read own" on public.notifications;
create policy "notifications read own" on public.notifications
  for select to authenticated using (to_uid = auth.uid());
drop policy if exists "notifications update own" on public.notifications;
create policy "notifications update own" on public.notifications
  for update to authenticated using (to_uid = auth.uid());
drop policy if exists "notifications insert any" on public.notifications;
create policy "notifications insert any" on public.notifications
  for insert to authenticated with check (true);

-- GIFTS (catalogue — everyone reads, no client writes)
drop policy if exists "gifts readable" on public.gifts;
create policy "gifts readable" on public.gifts
  for select to authenticated using (true);

-- COIN PURCHASES
drop policy if exists "coin purchases self all" on public.coin_purchases;
create policy "coin purchases self all" on public.coin_purchases
  for all to authenticated using (uid = auth.uid())
  with check (uid = auth.uid());

-- ============================================================
-- STORAGE BUCKETS (can also be created in the Supabase UI)
-- ============================================================
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('chat_media', 'chat_media', true)
on conflict (id) do nothing;

-- NOTE: storage.objects.owner_id is TEXT (not uuid). Comparing it to the
-- uuid-returning auth.uid() fails with "ERROR 42883: operator does not exist:
-- text = uuid". CAST(...) makes the comparison safe on any Supabase version.
drop policy if exists "avatars public read" on storage.objects;
create policy "avatars public read" on storage.objects
  for select using (bucket_id = 'avatars');
drop policy if exists "avatars own upload" on storage.objects;
create policy "avatars own upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'avatars');
drop policy if exists "avatars own update" on storage.objects;
create policy "avatars own update" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and cast(owner_id as text) = cast(auth.uid() as text));
drop policy if exists "avatars own delete" on storage.objects;
create policy "avatars own delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and cast(owner_id as text) = cast(auth.uid() as text));

drop policy if exists "chat media public read" on storage.objects;
create policy "chat media public read" on storage.objects
  for select using (bucket_id = 'chat_media');
drop policy if exists "chat media upload" on storage.objects;
create policy "chat media upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'chat_media');
