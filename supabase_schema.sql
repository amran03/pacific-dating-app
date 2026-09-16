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
  -- Mapendeleo ya faragha (Profile > Settings) — yanaathiri tabia halisi:
  -- read_receipts  -> seen ticks zinatumwa/zinapokelewa
  -- typing_indicator -> "anaandika..." inaonekana kwa mwenzake
  -- show_online    -> "Online"/last seen inaonekana kwa wengine
  -- discoverable   -> unaonekana kwenye Discover (swipe cards)
  read_receipts_enabled boolean not null default true,
  typing_indicator_enabled boolean not null default true,
  show_online_status_enabled boolean not null default true,
  discoverable boolean not null default true,
  -- vibration -> simu inatetema kwa arifa mpya
  -- sound     -> sauti inapigwa kwa arifa mpya
  vibration_enabled boolean not null default true,
  sound_enabled boolean not null default true,
  is_online boolean not null default false,
  last_seen text,
  is_profile_complete boolean not null default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
-- Idempotent migration: huongeza columns mpya kama table ilikuwepo tayari
-- kutoka version ya awali ya app. Salama ku-run mara nyingi.
do $$
declare
  col text;
begin
  foreach col in array array[
    'chat_unlock_price',
    'location_enabled',
    'notifications_enabled',
    'read_receipts_enabled',
    'typing_indicator_enabled',
    'show_online_status_enabled',
    'discoverable',
    'vibration_enabled',
    'sound_enabled',
    'is_online',
    'is_profile_complete'
  ] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'users' and column_name = col
    ) then
      if col in ('location_enabled', 'is_online', 'is_profile_complete') then
        execute format('alter table public.users add column %I boolean not null default false', col);
      elsif col = 'notifications_enabled' then
        execute format('alter table public.users add column %I boolean not null default true', col);
      elsif col in ('read_receipts_enabled', 'typing_indicator_enabled', 'show_online_status_enabled', 'discoverable', 'vibration_enabled', 'sound_enabled') then
        execute format('alter table public.users add column %I boolean not null default true', col);
      elsif col = 'chat_unlock_price' then
        execute format('alter table public.users add column %I int not null default 0', col);
      else
        execute format('alter table public.users add column %I boolean', col);
      end if;
    end if;
  end loop;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users' and column_name = 'last_seen'
  ) then
    alter table public.users add column last_seen text;
  end if;
end $$;



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

-- Chat lock: `unlocked_by` inaorodhesha walioLIPA kufungua chat (milele).
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'chat_rooms' and column_name = 'unlocked_by'
  ) then
    alter table public.chat_rooms add column unlocked_by uuid[] not null default '{}';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'chat_rooms' and column_name = 'typing'
  ) then
    alter table public.chat_rooms add column typing uuid;
  end if;
end $$;
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
  type text not null default 'message', -- match | message | gift | coins | missed_call
  title text not null default '',
  description text not null default '',
  read boolean not null default false,
  created_at timestamptz default now()
);

-- Missed calls huhitaji taarifa za anayetuma (kwa ajili ya avatar/jina
-- kwenye section ya "Missed Calls"). Idempotent — salama ku-run mara nyingi.
alter table public.notifications add column if not exists from_uid uuid;
alter table public.notifications add column if not exists from_name text;

-- ---------- GIFTS SENT (historia ya zawadi zilizotumwa) ----------
-- INAUNDWA HAPA (kabla ya triggers hapo chini) ili script i-run kwa
-- mpangilio sahihi: kwanza table, kisha triggers zinazoirejelea.
create table if not exists public.gifts_sent (
  id uuid primary key default gen_random_uuid(),
  from_uid uuid not null references auth.users (id) on delete cascade,
  to_uid uuid not null references auth.users (id) on delete cascade,
  gift_id text not null default '',
  gift_name text not null default '',
  gift_emoji text not null default '',
  gift_image_url text not null default '',
  coin_cost int not null default 0,
  sent_at timestamptz default now(),
  created_at timestamptz default now()
);

-- GIFTS (catalogue — everyone reads, no client writes)
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

-- ---------- USER STATS (likes + gifts + rating — counters za umma) ----------
-- Counters hizi husasishwa na triggers hapa chini, UI inazisoma moja kwa
-- moja kutoka public.users (select tayari inaruhusiwa kwa authenticated).
alter table public.users add column if not exists likes_received_count int not null default 0;
alter table public.users add column if not exists gifts_received_count int not null default 0;
alter table public.users add column if not exists gifts_received_value int not null default 0;
alter table public.users add column if not exists rating_sum bigint not null default 0;
alter table public.users add column if not exists rating_count int not null default 0;

-- Trigger: kila like mpya ('like' kwenye swipes) inaongeza counter ya mpokeaji.
create or replace function public.bump_likes_received()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' and NEW.action = 'like' then
    update public.users set likes_received_count = likes_received_count + 1
    where uid = NEW.target_uid;
  elsif TG_OP = 'UPDATE' and OLD.action is distinct from NEW.action then
    if NEW.action = 'like' then
      update public.users set likes_received_count = likes_received_count + 1
      where uid = NEW.target_uid;
    else
      update public.users set likes_received_count = greatest(likes_received_count - 1, 0)
      where uid = OLD.target_uid;
    end if;
  elsif TG_OP = 'DELETE' and OLD.action = 'like' then
    update public.users set likes_received_count = greatest(likes_received_count - 1, 0)
    where uid = OLD.target_uid;
  end if;
  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end $$;
drop trigger if exists trg_bump_likes_received on public.swipes;
create trigger trg_bump_likes_received
  after insert or update or delete on public.swipes
  for each row execute function public.bump_likes_received();

-- Trigger: kila zawadi inayoingizwa kwenye gifts_sent inaongeza counter + thamani.
create or replace function public.bump_gifts_received()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.users
  set gifts_received_count = gifts_received_count + 1,
      gifts_received_value = gifts_received_value + coalesce(NEW.coin_cost, 0)
  where uid = NEW.to_uid;
  return NEW;
end $$;
drop trigger if exists trg_bump_gifts_received on public.gifts_sent;
create trigger trg_bump_gifts_received
  after insert on public.gifts_sent
  for each row execute function public.bump_gifts_received();

-- ---------- COIN PURCHASES ----------
create table if not exists public.coin_purchases (
  id uuid primary key default gen_random_uuid(),
  uid uuid not null references auth.users (id) on delete cascade,
  coins int not null default 0,
  amount numeric not null default 0,
  created_at timestamptz default now()
);

-- ---------- RATINGS (nyota 1-5 kwa wasifu) ----------
create table if not exists public.ratings (
  from_uid uuid not null references auth.users (id) on delete cascade,
  to_uid uuid not null references auth.users (id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (from_uid, to_uid),
  check (from_uid <> to_uid)
);

alter table public.ratings enable row level security;

-- NOTE: RLS policies za ratings ziko chini kwenye section ya RLS
-- (pamoja na gifts_sent) ili zote zi-run baada ya ENABLE ROW LEVEL SECURITY.

create or replace function public.apply_rating_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    update public.users
    set rating_sum = rating_sum + NEW.stars,
        rating_count = rating_count + 1
    where uid = NEW.to_uid;
    return NEW;
  elsif TG_OP = 'UPDATE' then
    update public.users
    set rating_sum = rating_sum - OLD.stars + NEW.stars
    where uid = NEW.to_uid;
    return NEW;
  elsif TG_OP = 'DELETE' then
    update public.users
    set rating_sum = greatest(rating_sum - OLD.stars, 0),
        rating_count = greatest(rating_count - 1, 0)
    where uid = OLD.to_uid;
    return OLD;
  end if;
  return NEW;
end $$;
drop trigger if exists trg_apply_rating_change on public.ratings;
create trigger trg_apply_rating_change
  after insert or update or delete on public.ratings
  for each row execute function public.apply_rating_change();


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
alter table public.gifts_sent enable row level security;
alter table public.ratings enable row level security;
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

-- ---------- SWIPES: ruhusu kusoma likes zako mwenyewe (Likes screen) ----------
-- Sera ya awali ("swipes self all") inaruhusu kusoma swipes zako TU
-- (from_uid = wewe), kwa hiyo Likes screen (target_uid = wewe) inarudisha
-- rows 0 kila wakati na inaonekana kama hakuna data. Tunaongeza sera ya
-- ziada bila kuivunja ya awali: mpokeaji anaweza kuona likes alizopokea.
drop policy if exists "swipes incoming likes readable" on public.swipes;
create policy "swipes incoming likes readable" on public.swipes
  for select to authenticated using (target_uid = auth.uid());

-- Realtime pia kwa tables mpya (salama ku-run tena).
do $$
declare t text;
begin
  foreach t in array array['gifts_sent', 'ratings'] loop
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

-- Mtumaji anaona alizotuma, mpokeaji anaona alizopokea.
drop policy if exists "gifts_sent participants read" on public.gifts_sent;
create policy "gifts_sent participants read" on public.gifts_sent
  for select to authenticated
  using (from_uid = auth.uid() or to_uid = auth.uid());
drop policy if exists "gifts_sent sender insert" on public.gifts_sent;
create policy "gifts_sent sender insert" on public.gifts_sent
  for insert to authenticated with check (from_uid = auth.uid());

-- GIFTS (catalogue — everyone reads, no client writes)
drop policy if exists "gifts readable" on public.gifts;
create policy "gifts readable" on public.gifts
  for select to authenticated using (true);

-- RATINGS (nyota 1-5): kila mtu anaona, kila mtu anaandika yake mwenyewe tu.
drop policy if exists "ratings readable" on public.ratings;
create policy "ratings readable" on public.ratings
  for select to authenticated using (true);
drop policy if exists "ratings self insert" on public.ratings;
create policy "ratings self insert" on public.ratings
  for insert to authenticated with check (from_uid = auth.uid());
drop policy if exists "ratings self update" on public.ratings;
create policy "ratings self update" on public.ratings
  for update to authenticated
  using (from_uid = auth.uid()) with check (from_uid = auth.uid());

-- ---------- RPC: SEND GIFT (atomic — punguzo + historia + notification) ----------
-- Kuitumia kunazuia "double spend" (row ya mtumaji inafungwa na FOR UPDATE)
-- na huruhusu kuandika gifts_sent + notifications bila kuvunja RLS
-- (function ina SECURITY DEFINER — ina-run na haki za owner, si za caller).
create or replace function public.send_gift(
  p_to_uid uuid,
  p_gift_id text,
  p_gift_name text,
  p_gift_emoji text default '',
  p_gift_image_url text default '',
  p_coin_cost int default 0,
  p_from_name text default 'Mtumiaji'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_from_uid uuid := auth.uid();
  v_balance int;
begin
  if v_from_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_to_uid = v_from_uid then
    raise exception 'CANNOT_GIFT_SELF';
  end if;
  if coalesce(p_coin_cost, 0) < 0 then
    raise exception 'INVALID_PRICE';
  end if;

  -- Funga row ya mtumaji ili kuzuia double-spend (bonyeza mara 2 haraka).
  select coins into v_balance from public.users where uid = v_from_uid for update;
  if not found then
    raise exception 'SENDER_NOT_FOUND';
  end if;
  if v_balance < coalesce(p_coin_cost, 0) then
    raise exception 'INSUFFICIENT_COINS';
  end if;

  update public.users
  set coins = coins - coalesce(p_coin_cost, 0),
      total_spent_coins = total_spent_coins + coalesce(p_coin_cost, 0),
      updated_at = now()
  where uid = v_from_uid;

  insert into public.gifts_sent
    (from_uid, to_uid, gift_id, gift_name, gift_emoji, gift_image_url, coin_cost)
  values
    (v_from_uid, p_to_uid, p_gift_id, p_gift_name,
     coalesce(p_gift_emoji, ''), coalesce(p_gift_image_url, ''),
     coalesce(p_coin_cost, 0));

  insert into public.notifications (to_uid, type, title, description, created_at, read)
  values (p_to_uid, 'gift', 'Umepokea Zawadi Mpya! 🎁',
    coalesce(p_from_name, 'Mtumiaji') || ' amekutumia ' ||
    coalesce(nullif(p_gift_emoji, ''), '🎁') || ' ' || p_gift_name || '.',
    now(), false);

  select coins into v_balance from public.users where uid = v_from_uid;
  return jsonb_build_object('ok', true, 'balance', v_balance);
end $$;

-- ---------- BACKFILL COUNTERS (kwa watumiaji waliopo — salama ku-run tena) ----------
-- Likes zilizopo kabla ya trigger (kwa waliopokea tu ndio tunasasisha).
update public.users u
set likes_received_count = coalesce(s.c, 0)
from (select target_uid, count(*) as c from public.swipes where action = 'like' group by target_uid) s
where u.uid = s.target_uid and u.likes_received_count = 0;

-- Gifts zilizopo kabla ya trigger.
update public.users u
set gifts_received_count = coalesce(g.c, 0),
    gifts_received_value = coalesce(g.v, 0)
from (select to_uid, count(*) as c, coalesce(sum(coin_cost), 0) as v
      from public.gifts_sent group by to_uid) g
where u.uid = g.to_uid and u.gifts_received_count = 0;

-- ---------- COIN PURCHASES RLS ----------
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
