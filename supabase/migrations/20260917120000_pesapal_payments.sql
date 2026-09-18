-- ============================================================
-- PACIFIC DATING APP — PesaPal (API 3.0) payments
-- Migration: jedwali la "transactions" + RLS + coins crediting
--
-- Run with:  supabase db push
-- (au paste kwenye Supabase Dashboard > SQL Editor > New query)
--
-- Idempotent: salama ku-run mara nyingi.
-- IMPORTANT: consumer_key / consumer_secret HAZIPO hapa — ziko
-- kwenye Supabase Edge Function secrets pekee.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TRANSACTIONS — kila order ya PesaPal inahifadhiwa hapa
-- ------------------------------------------------------------
create table if not exists public.transactions (
  id text primary key,                           -- order id: "PACIFIC-<uid>-<timestamp>"
  uid uuid not null references auth.users (id) on delete cascade,
  amount numeric not null check (amount > 0),    -- kiasi cha TZS kilicholipwa
  coins int not null default 0,                  -- coins zilizonunuliwa (1 coin = 100 TZS)
  currency text not null default 'TZS',
  description text,
  status text not null default 'PENDING'
    check (status in ('PENDING', 'COMPLETED', 'FAILED')),
  order_tracking_id text,                        -- PesaPal order_tracking_id
  merchant_reference text,                       -- PesaPal merchant_reference
  payment_method text,                           -- mf. "Mpesa", "Card"
  payment_status_description text,               -- mf. "Completed"
  pesapal_status jsonb,                          -- JSON ghafi kutoka GetTransactionStatus
  credited boolean not null default false,       -- true = coins zimeongezwa (idempotency)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Idempotent migration: ongeza columns mpya kama jedwali lilikuwepo tayari.
do $$
declare
  col text;
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'transactions'
  ) then
    foreach col in array array[
      'coins', 'currency', 'description', 'merchant_reference',
      'payment_method', 'payment_status_description', 'pesapal_status',
      'credited', 'updated_at'
    ] loop
      if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'transactions' and column_name = col
      ) then
        if col = 'coins' then
          execute 'alter table public.transactions add column coins int not null default 0';
        elsif col = 'credited' then
          execute 'alter table public.transactions add column credited boolean not null default false';
        elsif col = 'updated_at' then
          execute 'alter table public.transactions add column updated_at timestamptz not null default now()';
        elsif col = 'currency' then
          execute format('alter table public.transactions add column %I text not null default %L', col, 'TZS');
        elsif col = 'pesapal_status' then
          execute format('alter table public.transactions add column %I jsonb', col);
        else
          execute format('alter table public.transactions add column %I text', col);
        end if;
      end if;
    end loop;
  end if;
end $$;

create index if not exists transactions_uid_created_idx
  on public.transactions (uid, created_at desc);
create index if not exists transactions_tracking_idx
  on public.transactions (order_tracking_id);

-- ------------------------------------------------------------
-- 2) ROW LEVEL SECURITY
--    - Mtumiaji anaweza KUSOMA rekodi zake mwenyewe tu.
--    - HAKUNA insert/update/delete policies: maandishi yote
--      yanafanyika kwa service_role ndani ya Edge Functions
--      (service_role inapita RLS).
-- ------------------------------------------------------------
alter table public.transactions enable row level security;

drop policy if exists "transactions select own" on public.transactions;
create policy "transactions select own" on public.transactions
  for select to authenticated using (auth.uid() = uid);

-- Realtime: ili PaymentWebViewScreen iweze kutumia .stream() badala ya polling.
alter table public.transactions replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'transactions'
     ) then
    execute 'alter publication supabase_realtime add table public.transactions';
  end if;
end $$;

-- ------------------------------------------------------------
-- 3) COINS column kwenye profile table
--    App hii inatumia public.users (uid + coins). Kama mradi wako
--    unatumia public.profiles, coins pia inaongezwa hapo.
-- ------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'users'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users' and column_name = 'coins'
  ) then
    alter table public.users add column coins int not null default 0;
  end if;

  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'profiles'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'coins'
  ) then
    alter table public.profiles add column coins int not null default 0;
  end if;
end $$;

-- ------------------------------------------------------------
-- 4) coin_purchases: columns zinazotumika kwenye app (buy_coins_screen)
-- ------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'coin_purchases'
  ) then
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'coin_purchases' and column_name = 'price_tsh'
    ) then
      alter table public.coin_purchases add column price_tsh numeric not null default 0;
    end if;
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'coin_purchases' and column_name = 'purchased_at'
    ) then
      alter table public.coin_purchases add column purchased_at timestamptz not null default now();
    end if;
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'coin_purchases' and column_name = 'status'
    ) then
      alter table public.coin_purchases add column status text not null default 'paid';
    end if;
  end if;
end $$;

-- ------------------------------------------------------------
-- 5) ATOMIC + IDEMPOTENT coin crediting
--
--    Inaitwa kwa service_role kutoka Edge Functions (pesapal-ipn /
--    pesapal-return) kupitia rpc('pesapal_credit_coins', ...).
--
--    Inahakikisha coins zinaongezwa MARA MOJA TU kwa kila order:
--    order inaweza "claim" tu kama status yake ilikuwa PENDING.
-- ------------------------------------------------------------
create or replace function public.pesapal_credit_coins(
  p_order_id text,
  p_coins int,
  p_status jsonb default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_amount numeric;
begin
  -- Claim order MARA MOJA: PENDING -> COMPLETED (+ credited = true).
  update public.transactions
     set status = 'COMPLETED',
         credited = true,
         pesapal_status = coalesce(p_status, pesapal_status),
         updated_at = now()
   where id = p_order_id
     and status = 'PENDING'
     and credited = false
  returning uid, amount into v_uid, v_amount;

  -- Order haipo au ilikwisha shughulikiwa -> usiongeze coins tena.
  if v_uid is null then
    return false;
  end if;

  -- 5a) Ongeza coins kwenye profile table.
  --     Kama rekodi ya mtumiaji haipo, itengenezwe (coins zisipotee).
  update public.users
     set coins = coalesce(coins, 0) + greatest(p_coins, 0)
   where uid = v_uid;

  if not found then
    insert into public.users (uid, coins)
    values (v_uid, greatest(p_coins, 0))
    on conflict (uid) do update
      set coins = coalesce(public.users.coins, 0) + greatest(p_coins, 0);
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'coins'
  ) then
    begin
      execute 'update public.profiles set coins = coalesce(coins, 0) + $1 where uid = $2'
        using greatest(p_coins, 0), v_uid;
    exception when undefined_column then
      begin
        execute 'update public.profiles set coins = coalesce(coins, 0) + $1 where id = $2'
          using greatest(p_coins, 0), v_uid;
      exception when others then
        raise warning 'profiles coins update skipped: %', sqlerrm;
      end;
    when others then
      raise warning 'profiles coins update skipped: %', sqlerrm;
    end;
  end if;

  -- 5b) Rekodi ununuzi (historia). Best-effort: kutofaulu kwake
  --     hakuathiri coins zilizoongezwa.
  begin
    insert into public.coin_purchases (uid, coins, amount)
    values (v_uid, greatest(p_coins, 0), coalesce(v_amount, 0));
  exception when others then
    raise warning 'coin_purchases insert skipped: %', sqlerrm;
  end;

  return true;
end;
$$;

-- Function hii ni ya service_role pekee — sio ya app (Dart) wala anon.
revoke all on function public.pesapal_credit_coins(text, int, jsonb) from public;
revoke all on function public.pesapal_credit_coins(text, int, jsonb) from anon;
revoke all on function public.pesapal_credit_coins(text, int, jsonb) from authenticated;
grant execute on function public.pesapal_credit_coins(text, int, jsonb) to service_role;