-- ============================================================
-- NOTIFICATIONS + MESSAGES VISIBILITY FIX
--
-- Tatizo 1: "Messages haziji kama notification"
--   _sendMessage() ina-insert row kwenye `notifications` yenye columns
--   (to_uid, from_uid, from_name, type, title, description, read).
--   DB za zamani zinaweza kukosa baadhi ya columns hizi au RLS insert
--   policy — insert inashindwa kimya na arifa haifikii mpokeaji.
--
-- Tatizo 2: "Count ya message haiondoki ukifungua ujumbe"
--   Badge inahesabu messages zenye seen=false. UPDATE ya seen inahitaji
--   RLS policy ya receiver (receiver_id = auth.uid()) — bila hiyo,
--   mark-as-seen inashindwa kimya na count inabaki milele.
--
-- Idempotent — salama ku-run mara nyingi.
-- ============================================================

-- ---------- NOTIFICATIONS: columns (DB za zamani zinaweza kukosa) ----------
alter table public.notifications
  add column if not exists to_uid uuid,
  add column if not exists from_uid uuid,
  add column if not exists from_name text not null default '',
  add column if not exists type text not null default 'message',
  add column if not exists title text not null default '',
  add column if not exists description text not null default '',
  add column if not exists read boolean not null default false,
  add column if not exists created_at timestamptz default now();

alter table public.notifications enable row level security;

-- Mpokeaji anaweza kusoma arifa zake.
drop policy if exists "notifications receiver readable" on public.notifications;
create policy "notifications receiver readable"
  on public.notifications
  for select to authenticated
  using (to_uid = auth.uid());

-- Mtumiaji yeyote aliyeingia anaweza kutuma arifa kwa mwenzake
-- (hivi ndivyo ujumbe mpya unavyomfikia mpokeaji kama notification).
drop policy if exists "notifications sender insert" on public.notifications;
create policy "notifications sender insert"
  on public.notifications
  for insert to authenticated
  with check (true);

-- Mpokeaji anaweza ku-mark arifa zake kama read (kufungua chat =
-- count na alama za "ujumbe mpya" zinaondoka).
drop policy if exists "notifications receiver update" on public.notifications;
create policy "notifications receiver update"
  on public.notifications
  for update to authenticated
  using (to_uid = auth.uid())
  with check (to_uid = auth.uid());

-- ---------- MESSAGES: receiver aweze ku-mark seen (count iondoke) ----------
alter table public.messages enable row level security;

-- Washiriki (mtumaji NA mpokeaji) wanaweza kusoma messages za chat.
drop policy if exists "messages participants readable" on public.messages;
create policy "messages participants readable"
  on public.messages
  for select to authenticated
  using (sender_id = auth.uid() or receiver_id = auth.uid());

-- Mtumiaji yeyote aliyeingia anaweza kutuma ujumbe.
drop policy if exists "messages sender insert" on public.messages;
create policy "messages sender insert"
  on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid());

-- Mpokeaji anaweza ku-mark messages zake kama seen — hii ndiyo
-- inaondoa count ya badge ukifungua chat.
drop policy if exists "messages receiver update seen" on public.messages;
create policy "messages receiver update seen"
  on public.messages
  for update to authenticated
  using (receiver_id = auth.uid())
  with check (receiver_id = auth.uid());

-- ---------- REALTIME: notifications + messages lazima ziwe live ----------
do $$
declare t text;
begin
  foreach t in array array['notifications', 'messages'] loop
    if exists (
      select 1 from information_schema.tables
      where table_schema = 'public' and table_name = t
    ) and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
