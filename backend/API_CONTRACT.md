# Cork Nights — API contract (frontend ⇄ Supabase)

The frontend talks to Supabase directly with **`@supabase/supabase-js` v2**. There is no custom server.
This file is everything the frontend needs: setup, the 4 calls, response shapes, nullability, validation limits and error handling.

---

## 0. Setup

```bash
npm install @supabase/supabase-js
```

```js
import { createClient } from '@supabase/supabase-js';

// Values come from env vars (see backend/.env.example). Use the anon / publishable key ONLY.
// e.g. Vite: import.meta.env.VITE_SUPABASE_URL, Next.js: process.env.NEXT_PUBLIC_SUPABASE_URL
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
```

> ❗ Never ship the `service_role` / `sb_secret_…` key to the browser. The anon key is designed to be public; Row Level Security protects the data.

### Device ID (needed for submitting reports)
Each browser gets a random ID that the database uses for rate limiting. Create it once and keep it in `localStorage`:

```js
export function getDeviceId() {
  let id = localStorage.getItem('cork_device_id');
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem('cork_device_id', id);
  }
  return id;
}
```

---

## Objects at a glance

| Name | Kind | Client access |
|---|---|---|
| `venues` | table | read |
| `reports` | table | read + **insert** (no update/delete) |
| `venue_summary` | view (one row per venue, aggregated) | read |
| `search_venues(...)` | RPC function → `venue_summary` rows | call |
| `music_tags()` | RPC function → `string[]` | call |
| `app_settings` | single-row table (window, thresholds, limits) | read |

---

## (a) List and filter venue cards

**Use the `search_venues` RPC.** It returns `venue_summary` rows (one per venue) and does the filtering for you.

```js
const { data: venues, error } = await supabase.rpc('search_venues', {
  max_pint: 6.5,          // number | null   only venues whose median pint ≤ €6.50
  music: ['techno'],      // string[] | null venue has ANY of these tags (case-insensitive)
  free_only: false,       // boolean         only venues whose recent reports say free entry
  max_age: 18,            // number | null   THE USER'S AGE; hides venues with min_age > this
  include_unpriced: false // boolean         with max_pint set, also keep venues with no recent pint price
});
```

Every parameter is optional. `supabase.rpc('search_venues')` with no arguments returns every venue.

**How `max_age` works:** pass the user's age (or the age bracket they choose). A venue is shown when `venue.min_age <= max_age`.
An 18-year-old (`max_age: 18`) never sees 21+ venues. `max_age: 21` (or `null`) shows everything.

**Default order:** cheapest median pint first (venues with no price last), then most recently reported, then name.
You can override the order and paginate by chaining, because the RPC returns rows of the view:

```js
const { data } = await supabase
  .rpc('search_venues', { music: ['house', 'techno'] })
  .order('report_count', { ascending: false })
  .range(0, 19);                       // first 20
```

Filters can also be chained onto the RPC (e.g. `.eq('type', 'club')`).

**Alternative without the RPC** (plain view query) if you prefer:

```js
let q = supabase.from('venue_summary').select('*');
if (maxPint != null) q = q.lte('median_pint_price', maxPint);   // note: excludes venues with no price
if (music)           q = q.overlaps('music', [music.toLowerCase()]);
if (freeOnly)        q = q.eq('free_entry', true);
if (userAge != null) q = q.lte('min_age', userAge);
const { data, error } = await q.order('median_pint_price', { ascending: true, nullsFirst: false });
```

### Music filter dropdown options

```js
const { data: tags } = await supabase.rpc('music_tags');
// ["disco","drum-and-bass","folk","hip-hop","house","indie","jazz","metal","pop","r&b","rock","soul","techno","trad"]
```

### Venue card row (`venue_summary` / `search_venues`) — example

```json
[
  {
    "id": 1,
    "name": "The Lee Lantern",
    "type": "bar",
    "music": ["trad", "folk"],
    "min_age": 18,
    "image_url": "https://picsum.photos/seed/lee-lantern/640/400",
    "created_at": "2026-11-07T12:50:29.896777+00:00",
    "median_pint_price": 5.7,
    "median_shot_price": 4,
    "median_mixer_price": 3.55,
    "free_entry": true,
    "entry_fee": 0,
    "report_count": 6,
    "last_reported": "2026-11-07T11:57:29.898938+00:00",
    "price_level": 1
  },
  {
    "id": 3,
    "name": "Mardyke Mill",
    "type": "club",
    "music": ["techno", "house"],
    "min_age": 21,
    "image_url": "https://picsum.photos/seed/mardyke-mill/640/400",
    "created_at": "2026-11-07T12:50:29.896777+00:00",
    "median_pint_price": 7,
    "median_shot_price": 5.7,
    "median_mixer_price": 4.8,
    "free_entry": false,
    "entry_fee": 15,
    "report_count": 10,
    "last_reported": "2026-11-07T12:21:29.898938+00:00",
    "price_level": 3
  }
]
```

A venue with **no recent reports** still appears, like this:

```json
{ "id": 21, "name": "New Place", "type": "bar", "music": ["pop"], "min_age": 18, "image_url": null,
  "created_at": "…", "median_pint_price": null, "median_shot_price": null, "median_mixer_price": null,
  "free_entry": null, "entry_fee": null, "report_count": 0, "last_reported": null, "price_level": null }
```

### Field reference

| Field | Type | Nullable | Meaning |
|---|---|---|---|
| `id` | number (int) | no | venue id |
| `name` | string | no | |
| `type` | `"bar"` \| `"club"` | no | |
| `music` | string[] | no (may be `[]`) | lowercase tags |
| `min_age` | number | no | 18, 21, … Show as "18+" / "21+" |
| `image_url` | string | **yes** | show a placeholder when null |
| `created_at` | string (ISO 8601) | no | when the venue was added |
| `median_pint_price` | number (€, 2dp) | **yes** | median over recent reports; null = no recent data |
| `median_shot_price` | number | **yes** | same |
| `median_mixer_price` | number | **yes** | same |
| `free_entry` | boolean | **yes** | majority of recent reports (tie ⇒ `false`); null = nobody said |
| `entry_fee` | number (€) | **yes** | `0` when `free_entry` is true; median reported fee when false; may be null if paid but no amount given |
| `report_count` | number | no | recent (in-window), non-flagged reports; `0` if none |
| `last_reported` | string (ISO) | **yes** | newest non-flagged report **ever** (not limited to the window) — use for "last report 25 min ago" |
| `price_level` | `1` \| `2` \| `3` | **yes** | €/€€/€€€ from the median pint; null when no pint price |

Numbers arrive as JSON numbers, so `5.70` arrives as `5.7`. Format with `toFixed(2)`.

**Suggested card rendering**
- Drink cost: `price_level ? '€'.repeat(price_level) : '?'`
- Entry: `free_entry === true` → "Free entry"; `false` → `entry_fee != null ? "€" + entry_fee : "Paid entry"`; `null` → "Entry unknown"
- Age: `${min_age}+`

**"Recent" window:** set in the database (`app_settings.summary_window`, default **4 hours**; for demos the team may set it to 7 days). You can read it with
`await supabase.from('app_settings').select('summary_window').single()` → `{ "summary_window": "04:00:00" }` (Postgres interval text).

**Price level thresholds** (default; editable in the DB): median pint ≤ €6.00 → 1, ≤ €6.80 → 2, otherwise 3.

---

## (b) Submit a report

```js
const { data, error } = await supabase
  .from('reports')
  .insert({
    venue_id: 3,          // required, an existing venue id
    pint_price: 6.8,      // number | null
    shot_price: null,     // number | null
    mixer_price: 4.5,     // number | null
    free_entry: false,    // boolean | null   (null = "don't know")
    entry_fee: 10,        // number | null    (0 = free)
    device_id: getDeviceId(), // required
  })
  .select('id, flagged, flag_reason')   // optional: get the result back
  .single();
```

Success response (`data`):

```json
{ "id": 123, "flagged": false, "flag_reason": null }
```

If the price looks wildly off compared with the venue's recent median, the report is **still saved** but flagged and ignored in the averages:

```json
{ "id": 124, "flagged": true, "flag_reason": "outlier: pint 40.00 vs median 6.80" }
```

### Only send these columns
`venue_id, pint_price, shot_price, mixer_price, free_entry, entry_fee, device_id`.
Sending `id`, `created_at`, `flagged` or `flag_reason` causes a `permission denied` error. The server sets those.

### Validation limits (enforced by the database, so mirror them in the form)

| Field | Rule |
|---|---|
| `venue_id` | required, must exist |
| `pint_price`, `shot_price`, `mixer_price` | optional; if given `> 0` and `≤ 100`; 2 decimal places (extra decimals are rounded) |
| `entry_fee` | optional; `≥ 0` and `≤ 100` |
| `free_entry` | optional boolean. `free_entry: true` with `entry_fee > 0` is **rejected** |
| at least one of | `pint_price`, `shot_price`, `mixer_price`, `free_entry`, `entry_fee` |
| `device_id` | required string, 8–64 chars (a UUID is 36) |
| rate limit | max **5 reports per venue per device per hour**, and **30 per device per hour** overall |

Convenience: `entry_fee: 0` with `free_entry` omitted is stored as free; `entry_fee > 0` alone is stored as paid; `free_entry: true` alone stores `entry_fee = 0`.

### Error handling

`error` is `{ code, message, details, hint }`.

| Situation | `error.code` | how to detect | example `message` |
|---|---|---|---|
| Rate limited | `P0001` | `error.hint === 'rate_limited'` | `Rate limit: max 5 reports per venue per hour. Try again later.` |
| Out-of-range / empty / contradictory values | `23514` | check violation | `new row for relation "reports" violates check constraint "reports_pint_price_check"` |
| Unknown venue | `42501` | | `new row violates row-level security policy for table "reports"` |
| Sent a server-only column | `42501` | | `permission denied for table reports` |

```js
if (error) {
  if (error.hint === 'rate_limited') showToast(error.message);
  else if (error.code === '23514')   showToast('Please check the prices you entered.');
  else                               showToast('Could not save report.');
}
```

---

## (c) Venues for the report-page dropdown

```js
const { data, error } = await supabase
  .from('venues')
  .select('id, name, type')
  .order('name');
```

```json
[
  { "id": 19, "name": "Afterglow", "type": "club" },
  { "id": 5,  "name": "Basement Nine", "type": "club" },
  { "id": 16, "name": "Bassline", "type": "club" }
]
```

`venues` columns: `id` (number), `name` (string), `type` (`"bar"|"club"`), `music` (string[]), `min_age` (number), `image_url` (string|null), `created_at` (ISO string). None are null except `image_url`.

---

## (d) Realtime: refresh cards when someone reports

New rows in `reports` are broadcast. Recommended pattern: listen for INSERTs and **re-fetch** the card list (debounced), because the medians are calculated in the database.

```js
let timer;
const channel = supabase
  .channel('reports-feed')
  .on(
    'postgres_changes',
    { event: 'INSERT', schema: 'public', table: 'reports' },
    (payload) => {
      const report = payload.new;          // the inserted row, see below
      clearTimeout(timer);
      timer = setTimeout(() => refetchCards(report.venue_id), 400);
    }
  )
  .subscribe((status) => console.log('realtime:', status)); // 'SUBSCRIBED' when connected

// on unmount / page leave:
supabase.removeChannel(channel);
```

To watch a single venue only (e.g. on a venue detail page):

```js
.on('postgres_changes',
    { event: 'INSERT', schema: 'public', table: 'reports', filter: 'venue_id=eq.3' },
    handler)
```

`payload.new` example:

```json
{
  "id": 125,
  "venue_id": 3,
  "pint_price": 6.9,
  "shot_price": null,
  "mixer_price": 4.6,
  "free_entry": false,
  "entry_fee": 15,
  "created_at": "2026-11-07T22:41:03.512+00:00",
  "device_id": "2c4aa4be-eddd-4174-82b2-f8eac53bef9c",
  "flagged": false,
  "flag_reason": null
}
```

Ignore events with `flagged: true` if you like; they don't change the summary.
Your own submission also triggers an event. It's simplest to re-fetch right after a successful insert as well, so the UI doesn't depend on the socket.

---

## Report row (`reports` table) reference

| Field | Type | Nullable |
|---|---|---|
| `id` | number | no |
| `venue_id` | number | no |
| `pint_price`, `shot_price`, `mixer_price` | number | yes |
| `free_entry` | boolean | yes |
| `entry_fee` | number | yes |
| `created_at` | ISO string (server time) | no |
| `device_id` | string | no |
| `flagged` | boolean | no |
| `flag_reason` | string | yes |

Raw reports for one venue (e.g. a "recent reports" list):

```js
const { data } = await supabase
  .from('reports')
  .select('id, pint_price, shot_price, mixer_price, free_entry, entry_fee, created_at')
  .eq('venue_id', 3)
  .eq('flagged', false)
  .order('created_at', { ascending: false })
  .limit(10);
```
