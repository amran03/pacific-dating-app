-- ============================================================
-- PACIFIC DATING APP — English-only gift notification
-- Migration: recreate public.send_gift with English user-facing text.
-- (The app is English-only now: notification title/description and the
-- default sender name must be in English.)
-- Safe to run: CREATE OR REPLACE, idempotent.
-- Run with:  supabase db push
-- ============================================================

create or replace function public.send_gift(
  p_to_uid uuid,
  p_gift_id text,
  p_gift_name text,
  p_gift_emoji text default '',
  p_gift_image_url text default '',
  p_coin_cost int default 0,
  p_from_name text default 'User'
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

  -- Lock the sender's row to prevent double-spend (two fast taps).
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
  values (p_to_uid, 'gift', 'You received a new gift! 🎁',
    coalesce(p_from_name, 'User') || ' sent you ' ||
    coalesce(nullif(p_gift_emoji, ''), '🎁') || ' ' || p_gift_name || '.',
    now(), false);

  select coins into v_balance from public.users where uid = v_from_uid;
  return jsonb_build_object('ok', true, 'balance', v_balance);
end $$;
