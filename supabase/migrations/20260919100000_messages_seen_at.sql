-- ============================================================
-- 20260919100000_messages_seen_at.sql
-- Unread badge + read receipts: kuongeza messages.seen_at
--
-- JINSI YA KU-RUN:
--   Supabase Dashboard > SQL Editor > New query > paste > RUN.
--   (Au endesha supabase_schema.sql nzima — pia ni idempotent.)
--
-- NI IDEMPOTENT: salama ku-run mara nyingi; inaongeza column tu
-- kama haipopo, na HAIBADILISHI data yoyote iliyopo.
--
-- APP INAVYOYOTUMIA:
--   Badge ya unread inahesabu messages zenye seen = false
--   (receiver_id = wewe). seen inageuka true NA seen_at inajazwa TU
--   pale chat yenyewe inapofunguliwa (individual_chat_screen ->
--   _markMessagesAsSeen) — si pale orodha ya messages inapofunguliwa.
--   App pia ina fallback: DB bila seen_at bado inafanya kazi.
-- ============================================================

alter table public.messages add column if not exists seen_at timestamptz;

-- (Optional) Kwa messages zilizokwishasomwa tayari (seen = true) ambazo
-- hazina seen_at, tumia created_at kama takriban ya wakati wa kusoma —
-- historia ikae na maana. Salama ku-run mara nyingi (inagusa rows
-- zenye seen_at null TU).
update public.messages
set seen_at = created_at
where seen = true and seen_at is null;

-- Kumbuka: Realtime ya messages (chaneli ya chat) hairuhusu Postgres
-- trigger za ziada hapa — hakuna trigger inayohitajika kwa seen_at.
