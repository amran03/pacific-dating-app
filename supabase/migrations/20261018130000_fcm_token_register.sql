-- ============================================================
-- 20261018130000_fcm_token_register.sql
-- NOTIFICATIONS NJE YA APP: FCM token LAZIMA ihifadhiwe kwenye
-- users.fcm_token — vinginevyo send-push inarudi sent:0 kila mara.
--
-- Tatizo la zamani: app ili-update users.fcm_token client-side, lakini
-- hakuna RLS UPDATE policy kwenye users -> update ilishindwa KIMYA
-- (rows 0 affected), token haikuwahi kuhifadhiwa, push za nje ya app
-- hazikuwahi kufika.
--
-- Suluhisho: RPC register_fcm_token (SECURITY DEFINER) — mtumiaji
-- anaweza kuhifadhi token YAKE TU (auth.uid()), hawezi kugusa coins
-- au columns nyingine. Client inaita RPC kwanza, fallback direct update.
--
-- JINSI YA KU-RUN: Supabase Dashboard > SQL Editor > paste > RUN
--   (au: supabase db push). NI IDEMPOTENT — salama ku-run mara nyingi.
-- ============================================================

alter table public.users
  add column if not exists fcm_token text;

create or replace function public.register_fcm_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_token is null or length(trim(p_token)) < 10 then
    raise exception 'INVALID_TOKEN';
  end if;
  update public.users
     set fcm_token = trim(p_token)
   where uid = v_me;
end;
$$;

revoke execute on function public.register_fcm_token(text)
  from public, anon;
grant execute on function public.register_fcm_token(text)
  to authenticated;