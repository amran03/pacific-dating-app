-- ============================================================
-- 20261018120000_atomic_coins_transfer.sql
-- COINS/ZAWADI: mpokeaji APATE coins zake NA HAKUTINGUKA ("make no
-- mistake").
--
-- Tatizo la zamani:
--   - App iliidhinisha rpc('send_gift') lakini function haikuwepo DB
--     -> ilishindwa kimya na legacy fallback iliendelea: mtumaji
--     alitozwa coins, MPokeaji hakuongezewa chochote.
--   - Kufungua chat (payAndUnlockChat) ilijaribu kuongeza coins za
--     mpokeaji client-side; RLS/mtandao ukishindwa, error ilinyamazwa
--     (catch swallow) -> mpokeaji kupoteza coins.
--
-- Suluhisho (hakuna hitilafu tena):
--   1) TRIGGER kwenye gifts_sent: kila row mpya (coin_cost > 0)
--      inaongeza coins za MPokeaji — SECURITY DEFINER (haizuiiwi na
--      RLS). Inafanya kazi kwa njia ZOTE (RPC, fallback, utendaji wowote
--      wa kuinsert gifts_sent).
--   2) RPC send_gift (atomic): hutoa mtumaji + kuweka gifts_sent
--      (mpokeaji anapewa coins na trigger) + notification.
--   3) RPC pay_and_unlock_chat (atomic): bei hutumwa payer -> receiver
--      + unlocked_by + notification — ndani ya transaction moja.
--
-- JINSI YA KU-RUN: Supabase Dashboard > SQL Editor > paste > RUN.
-- NI IDEMPOTENT — salama ku-run mara nyingi.
-- ============================================================

-- ---------- 1) Trigger: kila zawadi = coins kwa mpokeaji ----------
create or replace function public.credit_receiver_coins()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.coin_cost, 0) > 0 then
    update public.users
       set coins = coalesce(coins, 0) + new.coin_cost
     where uid = new.to_uid;
  end if;
  return new;
end;
$$;

drop trigger if exists gifts_sent_credit_receiver on public.gifts_sent;
create trigger gifts_sent_credit_receiver
  after insert on public.gifts_sent
  for each row
  execute function public.credit_receiver_coins();

-- ---------- 2) RPC send_gift (atomic) ----------
create or replace function public.send_gift(
  p_to_uid uuid,
  p_gift_id text,
  p_gift_name text,
  p_gift_emoji text default '',
  p_gift_image_url text default '',
  p_coin_cost int default 0,
  p_from_name text default 'User'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from uuid := auth.uid();
  v_my_coins int;
  v_cost int := coalesce(p_coin_cost, 0);
begin
  if v_from is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_to_uid is null or p_to_uid = v_from then
    raise exception 'INVALID_RECIPIENT';
  end if;

  -- Pata + Funga salio la mtumaji (FOR UPDATE — zuia race ya kutuma
  -- mara mbili kwa wakati mmoja).
  select coalesce(coins, 0) into v_my_coins
    from public.users where uid = v_from for update;

  if v_my_coins < v_cost then
    raise exception 'INSUFFICIENT_COINS';
  end if;

  -- 1. Toza mtumaji.
  if v_cost > 0 then
    update public.users set coins = coins - v_cost where uid = v_from;
  end if;

  -- 2. Rekodi zawadi — trigger (hapo juu) inaongeza coins za MPokeaji
  --    MOJA KWA MOJA hapa. Hakuna njia ambayo mpokeaji anasahau.
  insert into public.gifts_sent
    (from_uid, to_uid, gift_id, gift_name, gift_emoji, gift_image_url,
     coin_cost, sent_at)
  values
    (v_from, p_to_uid, p_gift_id, p_gift_name, p_gift_emoji,
     p_gift_image_url, v_cost, now());

  -- 3. Notification ya app.
  insert into public.notifications
    (to_uid, from_uid, from_name, type, title, description, read, created_at)
  values
    (p_to_uid, v_from, p_from_name, 'gift',
     'You received a New Gift! 🎁',
     p_from_name || ' sent you ' ||
       coalesce(nullif(p_gift_emoji, ''), '🎁') || ' ' || p_gift_name,
     false, now());

  -- 4. Takwimu za profile (best-effort — columns zinaweza kukosa kwenye
  --    DB za zamani).
  begin
    update public.users
       set gifts_received_count = coalesce(gifts_received_count, 0) + 1,
           gifts_received_value =
             coalesce(gifts_received_value, 0) + v_cost
     where uid = p_to_uid;
  exception when undefined_column then
    null;
  end;
end;

-- ---------- 3) RPC pay_and_unlock_chat (atomic) ----------
create or replace function public.pay_and_unlock_chat(p_other_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_price int;
  v_my_coins int;
  v_chat_id text;
  v_unlocked_by jsonb;
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_other_uid is null or p_other_uid = v_me then
    raise exception 'INVALID_RECIPIENT';
  end if;

  select coalesce(chat_unlock_price, 0) into v_price
    from public.users where uid = p_other_uid;

  -- chat_id: uid zote mbili zimepangwa, zimeunganishwa na '_' (app rule).
  select string_agg(x, '_' order by x) into v_chat_id
    from (select v_me::text as x
          union all
          select p_other_uid::text) t;

  if coalesce(v_price, 0) > 0 then
    select coalesce(coins, 0) into v_my_coins
      from public.users where uid = v_me for update;

    if v_my_coins < v_price then
      raise exception 'INSUFFICIENT_COINS';
    end if;

    -- Toza payer + lipa receiver — transaction moja, haiwezi kushindwa
    -- nusu (hakuna "nimelezwa lakini hakuna lipuo").
    update public.users set coins = coins - v_price where uid = v_me;
    update public.users
       set coins = coalesce(coins, 0) + v_price
     where uid = p_other_uid;
  end if;

  -- Fungua chat (unlocked_by = orodha ya JSONb ya uid).
  select unlocked_by into v_unlocked_by
    from public.chat_rooms where id = v_chat_id;
  if v_unlocked_by is null then
    v_unlocked_by = '[]'::jsonb;
  end if;
  if not (v_unlocked_by ? v_me::text) then
    v_unlocked_by := v_unlocked_by || to_jsonb(v_me::text);
  end if;

  insert into public.chat_rooms (id, participants, unlocked_by, last_message_at)
  values (
    v_chat_id,
    array[v_me::text, p_other_uid::text],
    v_unlocked_by,
    now()
  )
  on conflict (id) do update
    set unlocked_by = excluded.unlocked_by,
        last_message_at = now();

  -- Notification ya coins kwa mpokeaji.
  if coalesce(v_price, 0) > 0 then
    insert into public.notifications
      (to_uid, from_uid, type, title, description, read, created_at)
    values
      (p_other_uid, v_me, 'coins', 'You received Coins! 🪙',
       (select coalesce(name, 'User') from public.users where uid = v_me) ||
         ' paid ' || v_price || ' Coins to unlock chat with you.',
       false, now());
  end if;
end;
$$;

revoke execute on function public.pay_and_unlock_chat(uuid)
  from public, anon;
grant execute on function public.pay_and_unlock_chat(uuid)
  to authenticated;

$$;

revoke execute on function public.send_gift(uuid, text, text, text, text, int, text)
  from public, anon;
grant execute on function public.send_gift(uuid, text, text, text, text, int, text)
  to authenticated;
