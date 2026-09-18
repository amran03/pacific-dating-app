-- ============================================================
-- LIKES VISIBILITY FIX — Likes screen (watu walioku-like)
--
-- Tatizo: Likes screen inaonyesha "Bado hakuna aliyekupenda" hata kama
-- kuna likes. Sababu:
--   1. RLS: bila policy ya "incoming likes", swipes zinazolenga wewe
--      (target_uid = wewe) zinarudishwa rows 0 (RLS inazificha).
--   2. Realtime: .stream() kwenye swipes inahitaji table iwe ndani ya
--      publication ya supabase_realtime — vinginevyo snapshot na
--      updates hazifiki app.
--
-- Idempotent — salama ku-run mara nyingi.
-- ============================================================

-- Hakikisha RLS imewashwa (salama; haibadilisha data).
alter table public.swipes enable row level security;

-- 1. Mpokeaji anaweza kusoma likes zilizomlenga.
drop policy if exists "swipes incoming likes readable" on public.swipes;
create policy "swipes incoming likes readable"
  on public.swipes
  for select to authenticated
  using (target_uid = auth.uid());

-- 2. Realtime publication — tables zote zinazotumika na .stream().
-- (Kila table inahakikiwa iipo kwanza — DB za zamani zinaweza kukosa
-- baadhi ya tables; hazitavurugwa.)
do $$
declare t text;
begin
  foreach t in array array['users', 'swipes', 'chat_rooms', 'messages',
                           'notifications', 'gifts_sent', 'ratings'] loop
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