# PesaPal (API 3.0) — Usanidi wa Pacific Dating App

Malipo yote yanafanyika **server side** kwenye Supabase Edge Functions.
`consumer_key` / `consumer_secret` HAZIPO kwenye Flutter na HAZIPO kwenye repo —
ziko kwenye **Supabase Edge Function secrets** pekee.

```
Flutter (lib/services/pesapal_service.dart)
   └─ supabase.functions.invoke('create-pesapal-order')   [JWT ya mtumiaji]
        └─ PesaPal API 3.0 (RequestToken → SubmitOrderRequest)
   └─ PaymentWebViewScreen  → redirect_url ya PesaPal (webview_flutter)
        └─ PesaPal → callback_url (pesapal-return)  +  IPN (pesapal-ipn)
             └─ GetTransactionStatus → transactions = COMPLETED/FAILED
                  └─ RPC pesapal_credit_coins() → users.coins += coins   [service_role]
```

## Faili zilizoongezwa

| Faili | Kazi |
| --- | --- |
| `supabase/migrations/20260917120000_pesapal_payments.sql` | jedwali `transactions`, RLS (select yake tu), `coins` kwenye profile, RPC `pesapal_credit_coins` (atomic + idempotent) |
| `supabase/functions/_shared/pesapal.ts` | PesaPal API 3.0 client: `getToken` (cache dakika 4), `registerIPN`, `submitOrder`, `getTransactionStatus` (Deno `fetch`) |
| `supabase/functions/_shared/order_status.ts` | thibitisha malipo + sasisha `transactions`/coins (inatumika na IPN na return) |
| `supabase/functions/register-pesapal-ipn/index.ts` | hupigwa **mara moja** kwa mkono → inarudisha `ipn_id` |
| `supabase/functions/create-pesapal-order/index.ts` | auth ya mtumiaji + kuunda order (TZS) + rekodi `PENDING` |
| `supabase/functions/pesapal-ipn/index.ts` | webhook ya PesaPal (bila auth ya mtumiaji) |
| `supabase/functions/pesapal-return/index.ts` | ukurasa wa HTML (callback_url) + fallback ya kuthibitisha malipo |
| `lib/services/pesapal_service.dart` | Flutter → Edge Function |
| `lib/features/profile/presentation/screens/payment_webview_screen.dart` | WebView ya PesaPal + kusubiri status (Realtime, kisha polling kila sekunde 2 × 6) |

## 0. Mahitaji (mara moja)

```bash
# Supabase CLI (Windows: scoop install supabase / npm i -g supabase)
supabase --version

# Deno (kwa ku-run functions kienyeji): https://deno.land/#installation
deno --version

supabase login
supabase link --project-ref <YOUR_PROJECT_REF>          # Project Settings → General → Reference ID
```

Kama hujawahi kuwa na `supabase/config.toml`:

```bash
supabase init        # inatengeneza supabase/config.toml
```

> **Repo hii ina `supabase/config.toml`** yenye `verify_jwt = false` kwa
> `pesapal-ipn`, `pesapal-return` na `register-pesapal-ipn`. Kama una faili
> yako tayari, nakili sehemu za `[functions.*]` ndani yake. Hivyo
> `supabase functions deploy` (bila jina la function) inatosha — hakuna haja
> ya `--no-verify-jwt` kwa kila function.

## 1. Weka secrets (HAZIWEKWI kwenye git)

```bash
supabase secrets set PESAPAL_CONSUMER_KEY=<consumer_key>
supabase secrets set PESAPAL_CONSUMER_SECRET=<consumer_secret>
supabase secrets set PESAPAL_ADMIN_SECRET=<neno_la_siri_lako_la_kulinda_register_function>

# ipn_id itawekwa baada ya hatua ya 3
supabase secrets list
```

## 2. Deploy Edge Functions

```bash
# (a) create-pesapal-order INAHITAJI JWT ya mtumiaji → deploy ya kawaida
supabase functions deploy create-pesapal-order

# (b) webhook + callback + register: PesaPal/mkono huitisha bila JWT
supabase functions deploy pesapal-ipn --no-verify-jwt
supabase functions deploy pesapal-return --no-verify-jwt
supabase functions deploy register-pesapal-ipn --no-verify-jwt

# Au deploy zote kwa mkupuo mmoja:
supabase functions deploy          # inasoma supabase/functions/*
```

Badala ya `--no-verify-jwt`, unaweza kuweka kwenye `supabase/config.toml`:

```toml
[functions.pesapal-ipn]
verify_jwt = false

[functions.pesapal-return]
verify_jwt = false

[functions.register-pesapal-ipn]
verify_jwt = false
```

## 3. Sajili IPN URL (MARA MOJA) kisha weka `PESAPAL_IPN_ID`

```powershell
# Windows PowerShell (inaepuka matatizo ya quoting) - tumia Invoke-RestMethod
$body = @{ ipnUrl = "https://<PROJECT_REF>.supabase.co/functions/v1/pesapal-ipn" } | ConvertTo-Json
Invoke-RestMethod -Method Post `
  -Uri "https://<PROJECT_REF>.supabase.co/functions/v1/register-pesapal-ipn" `
  -Headers @{ "x-admin-secret" = "<PESAPAL_ADMIN_SECRET>" } `
  -ContentType "application/json" `
  -Body $body
```

```bash
# macOS / Linux / Git Bash
curl -X POST "https://<PROJECT_REF>.supabase.co/functions/v1/register-pesapal-ipn" \
  -H "x-admin-secret: <PESAPAL_ADMIN_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"ipnUrl":"https://<PROJECT_REF>.supabase.co/functions/v1/pesapal-ipn"}'
```

Jibu: `{"ok":true,"ipn_id":"<IPN_ID>", ...}`

```bash
supabase secrets set PESAPAL_IPN_ID=<IPN_ID>
# Hakuna haja ya redeploy — function inasoma secret mpya mara moja.
```

Kama function ilikwisha sajili URL hiyo (rerun), inarudisha `"reused":true` na `ipn_id` ile ile.

## 4. Endesha migration (jedwali + RLS + coins)

```bash
supabase db push                       # inatumia supabase/migrations/*
```

Au: Supabase Dashboard → **SQL Editor** → paste faili la migration → Run.
Kuona SQL ambayo itaendeshwa bila kuigusa database:
```bash
supabase db push --dry-run
```

## 5. Sandbox / Test

- Production (default): `https://pay.pesapal.com/v3/api` — ipo kwenye
  `supabase/functions/_shared/pesapal.ts` (`PESAPAL_BASE_URL`).
- Sandbox: `https://cybqa.pesapal.com/pesapalv3/api` (badilisha constant,
  tumia sandbox keys, deploy tena, na sajili IPN ya sandbox).
- Kumbuka: IPN URL LAZIMA iwe `https://` (PesaPal hairuhusu `http`).

## 6. Kuipa mtumiaji coins kwa mkono (kama IPN iligoma)

```bash
supabase functions invoke pesapal-ipn \
  --body '{"OrderTrackingId":"<order_tracking_id>","OrderMerchantReference":"<PACIFIC-order-id>"}'
```

`supabase secrets set ...` pamoja na `supabase functions deploy` pia zinaweza kufanyika
kutoka Dashboard: **Edge Functions → Secrets**.

## 7. Flutter — mfano wa kuitisha `PesapalService`

Umeunganishwa tayari kwenye `lib/features/profile/presentation/screens/buy_coins_screen.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/services/pesapal_service.dart';
import 'package:pacific_dating_app/features/profile/presentation/screens/payment_webview_screen.dart';

Future<void> buyCoins(int coins) async {
  // uid + email zinachukuliwa kutoka Auth (FLUTTER HAINA SECRET YOYOTE).
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    // mwambie mtumiaji aingie (sign in) kwanza
    return;
  }

  try {
    // 1) Server inahesabu kiasi (1 coin = 100 TZS), inaunda order kwa PesaPal,
    //    inahifadhi transactions = PENDING (service_role).
    final order = await PesapalService.instance.createOrder(
      coins: coins,
      description: '$coins Pacific Coins',
      email: user.email,          // Auth email
      phone: '+255712345678',     // au acha wazi: Edge Function inasoma users.phone_number
    );

    // 2) Lipa kwenye WebView; inarudisha true/false/null.
    if (!mounted) return;
    final bool? paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaymentWebViewScreen(
          redirectUrl: order.redirectUrl,
          orderId: order.orderId,   // PACIFIC-<uid>-<timestamp>
        ),
      ),
    );

    // 3) Coins zinaongezwa na Edge Function (pesapal-ipn / pesapal-return).
    if (paid == true) {
      // onyesha "Umepata coins ${order.coins}"
    } else if (paid == false) {
      // onyesha "Malipo yameshindwa"
    } else {
      // haijathibitishwa bado — coins zitaongezwa zikithibitishwa
    }
  } on PesapalException catch (e) {
    // e.message inaonyeshwa kwa mtumiaji
  }
}
```

Salio la coins (Realtime + RLS: mtumiaji anaona chake tu):

```dart
StreamBuilder<List<Map<String, dynamic>>>(
  stream: Supabase.instance.client
      .from('users')
      .stream(primaryKey: ['uid'])
      .eq('uid', Supabase.instance.client.auth.currentUser!.id),
  builder: (context, snapshot) {
    final coins = (snapshot.data?.isNotEmpty ?? false)
        ? (snapshot.data!.first['coins'] ?? 0) as int
        : 0;
    return Text('$coins coins');
  },
)
```

Kusoma rekodi moja ya malipo:

```dart
final row = await Supabase.instance.client
    .from('transactions')
    .select()
    .eq('id', orderId)
    .maybeSingle();     // RLS: inarudisha null kwa order ya mtu mwingine
```

## 8. Checklist ya usalama

- [x] `consumer_secret` ipo kwenye Supabase secrets pekee (Flutter/repo haina).
- [x] `transactions`: RLS - `select` ya `auth.uid() = uid` tu; hakuna policies za
      insert/update `authenticated` (maandishi = `service_role` tu).
- [x] Kiasi (TZS) KINAHESABIWA server side (`coins × 100`) - client haiaminiki.
- [x] Coins zinaongezwa kwa `pesapal_credit_coins()` (atomic claim: PENDING → COMPLETED
      + `credited = true`), kwa hiyo IPN ikipigwa mara nyingi coins haziongezwi mara mbili.
- [x] Coins zinaongezwa tu baada ya `GetTransactionStatus` kurudisha `status_code = 1`.
- [x] `register-pesapal-ipn` inalindwa na `x-admin-secret` / service-role bearer.
