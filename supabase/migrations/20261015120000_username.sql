-- @username ya kipekee (handle) — TOFAUTI na name ya kuonyeshwa.
-- Hii ndiyo "user name" ya lazima; mtumiaji anaweza kubadilisha mara moja
-- kwa mwezi (kikomo kinaongozwa na username_changed_at / name_changed_at).

-- 1) Handle ya kipekee (nullable kwa sasa ili watu wa zamani waingie taratibu;
--    app inalazimisha kuwepo kabla ya kuhifadhi wasifu).
alter table public.users
  add column if not exists username text;

-- 2) Wakati wa kubadilisha mara ya mwisho (kwa kikomo cha mwezi 1).
alter table public.users
  add column if not exists username_changed_at timestamptz;
alter table public.users
  add column if not exists name_changed_at timestamptz;

-- 3) Kizuizi cha kipekee cha kesi-insensitive (aa == AA). NULL nyingi
--    zinaruhusiwa (Postgres unique index haizuii NULL nyingi).
create unique index if not exists users_username_lower_key
  on public.users (lower(username));

-- 4) Onyesha username kwenye utafuti (search) — index rahisi.
create index if not exists users_username_idx
  on public.users (username)
  where username is not null;

-- 5) RLS: users tayari ina policies; hakikisha arifa/hisia mpya zinaweza
--    kusomwa na kuhaririwa na mmiliki (hakuna badiliko la msingi la RLS).
--    (Weka username kwenye faili moja — hakuna uboreshaji wa policy hapa.)