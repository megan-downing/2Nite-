# Cork Nights — backend (Supabase)

Crowdsourced, Waze-style drink prices and entry info for bars and clubs in Cork.
The whole backend is **Supabase** (hosted Postgres + its auto-generated API). There is no custom server.
The frontend uses `@supabase/supabase-js` directly; see **[API_CONTRACT.md](./API_CONTRACT.md)**.

```
backend/
├── README.md                     ← you are here
├── API_CONTRACT.md               ← for the frontend teammate
├── .env.example                  ← SUPABASE_URL / SUPABASE_ANON_KEY placeholders
├── supabase/
│   ├── migrations/
│   │   ├── 0001_tables.sql             settings, venues, reports, constraints, indexes
│   │   ├── 0002_abuse_protection.sql   rate limiting + outlier flagging trigger
│   │   ├── 0003_security.sql           Row Level Security + permissions
│   │   ├── 0004_venue_summary.sql      venue_summary view + search_venues() + music_tags()
│   │   └── 0005_realtime.sql           turn on Realtime for reports
│   ├── seed.sql                  ← 20 demo venues + recent reports (re-run = fresh data)
│   ├── verify.sql                ← self-test, prints PASS/FAIL
│   └── reset.sql                 ← deletes everything (start over)
└── test-client/
    ├── index.html                ← standalone test page (no build step)
    └── config.example.js         ← copy to config.js and add your URL/key
```

---

## 1. Create a Supabase project (≈3 min)

1. Go to **https://supabase.com** → **Start your project** → sign up (GitHub login is quickest).
2. You'll be asked to create an **organization**. Any name is fine, **Free** plan.
3. Click **New project** and fill in:
   - **Project name:** `cork-nights` (anything)
   - **Database password:** click **Generate a password** and save it somewhere. You won't need it for this guide.
   - **Region:** **West EU (Ireland)**, closest to Cork.
   - If you see **Security / Data API options**: leave **"Enable Data API"** ticked (the frontend needs it). The other ticks don't matter, because our SQL sets its own permissions and RLS.
4. Click **Create new project** and wait 1–2 minutes until the dashboard finishes "Setting up project".

## 2. Run the SQL files (in order)

Do this for **each file below, one at a time, in this exact order**:

| # | File |
|---|---|
| 1 | `supabase/migrations/0001_tables.sql` |
| 2 | `supabase/migrations/0002_abuse_protection.sql` |
| 3 | `supabase/migrations/0003_security.sql` |
| 4 | `supabase/migrations/0004_venue_summary.sql` |
| 5 | `supabase/migrations/0005_realtime.sql` |
| 6 | `supabase/seed.sql` |
| 7 | `supabase/verify.sql` (optional but recommended) |

How:
1. In the left sidebar of your project, click **SQL Editor** (the `>_` icon).
2. Click **+ New query** (or the **+** tab at the top).
3. Open the file on your computer (or on GitHub), **copy the entire contents**, and paste into the editor.
4. Click **Run** (bottom-right) or press **Ctrl+Enter** / **Cmd+Enter**.
5. You should see **"Success. No rows returned"** (files 1–5), a table of 20 venues (file 6), or the PASS/FAIL table (file 7).
   - If Supabase shows a **"Potential issue detected… destructive operation"** popup (it appears for `seed.sql` and `reset.sql` because they delete data), click **Run this query**.
6. Repeat with a new query (or replace the editor contents) for the next file.

All migration files are **safe to re-run**. If you're unsure whether one ran, just run it again.

**What to check:**
- Left sidebar → **Table Editor**: you should see `app_settings`, `reports`, `venues`. `venues` has 20 rows, `reports` ~120.
- `seed.sql` ends by printing a table: 20 venues, each with a `price_level` (1–3), `median_pint_price`, and `report_count` 3–10.
- `verify.sql` prints ~20 rows and **every `result` should be `PASS`**. It runs the checks as the public `anon` role (what the website uses), so this proves that reading the view, the RPC, inserting, the blocked update/delete, the rate limit, outlier flagging and Realtime all work. It cleans up after itself.

## 3. Get the Project URL and anon key

1. Click the **Connect** button at the top of the dashboard, **or** go to **Project Settings** (⚙ gear, bottom of the left sidebar).
2. **Project URL**: shown in the Connect dialog (App Frameworks tab), or **Project Settings → Data API** → *Project URL*. It looks like `https://abcdefghijklmnop.supabase.co`.
3. **Key**: **Project Settings → API Keys**.
   - Use the **Publishable key** (`sb_publishable_…`), **or** under the **Legacy API keys** tab the **`anon` `public`** key (a long `eyJ…` string). Either works as `SUPABASE_ANON_KEY`.
   - ❌ **Never** use the `service_role` or **Secret key** (`sb_secret_…`) in the website, the test page, or git.
4. Copy `backend/.env.example` to `backend/.env` and paste the values in. `.env` is gitignored. Share the URL and key with the frontend teammate. They're safe to use in the browser, because RLS protects the data.

## 4. Realtime

`0005_realtime.sql` already enabled it. To confirm in the dashboard:
- Left sidebar → **Database** → **Publications** → row **`supabase_realtime`** → the **`reports`** table toggle is **on**.
  (Equivalent: **Table Editor → reports**, which shows a "Realtime" badge/toggle on the table.)
- If it's off, flip it on there. That's the same thing the SQL file does.

## 5. Run the test page

The test page proves the backend works before the real frontend exists.

1. In `backend/test-client/`, copy `config.example.js` to **`config.js`** and fill in your Project URL and key. (`config.js` is gitignored. You can instead edit the `CONFIG` constant at the top of the `<script>` in `index.html`, but then don't commit it.)
2. Open it. Either:
   - **Double-click `index.html`** (opens as `file://…` in your browser; this works), or
   - serve it locally (more reliable):
     ```bash
     cd backend/test-client
     python3 -m http.server 8080
     ```
     then open http://localhost:8080
3. **What you should see:**
   - The pill at the top shows **`realtime: subscribed`** (green) and `window: 04:00:00`.
   - 20 venue cards with €/€€/€€€, free/paid entry, music tags and 18+/21+.
   - The filters work: **I am 18–20** hides the six 21+ venues; **Music: techno** shows 3; **Max pint 6** shows only cheap bars; **Free entry only** hides paid clubs.
4. **Test reporting:** pick a venue, enter a pint price, and click **Submit report** → "Thanks! Report #… saved", and the card updates.
   - Submit 6 times for the same venue → the 6th shows the **rate-limit** message.
   - Enter a pint of **40** → "Saved, but flagged as unusual…" and the averages don't change.
   - Enter **150** → rejected (the max is 100).
5. **Test realtime:** open the page in **two browser windows** (or a normal and an incognito window, which get different device IDs). Submit in one; the other shows the report under **Live activity** and refreshes that card within a second.

## 6. Demo mode, settings and adding venues

The summary only counts reports from the **last 4 hours** (a night out). Seed data is timestamped "now minus up to ~4 h" when you run `seed.sql`, so a few hours later the cards go empty.
For demos, either re-run `seed.sql` right before demoing, or widen the window (SQL Editor):

```sql
update public.app_settings set summary_window = '7 days';   -- demo mode
update public.app_settings set summary_window = '4 hours';  -- back to live mode
```

Other knobs (same table, take effect immediately):

```sql
update public.app_settings set price_level_1_max = 6.00, price_level_2_max = 6.80; -- €/€€/€€€ pint thresholds
update public.app_settings set rate_limit_per_venue_hour = 5, rate_limit_total_hour = 30;
update public.app_settings set outlier_factor = 2.5;  -- flag prices >2.5× or <1/2.5 of the venue median
```

The defaults live at the top of `0001_tables.sql`. Note that **re-running `0001_tables.sql` resets these settings to the values in that file**.

**Add a venue** (venues are added manually; the website can't add them):

```sql
insert into public.venues (name, type, music, min_age, image_url)
values ('The New Spot', 'bar', array['indie','rock'], 18, 'https://picsum.photos/seed/new-spot/640/400');
```

or use **Table Editor → venues → Insert → Insert row**. Music tags must be **lowercase**. `type` is `bar` or `club`.

**Moderation:** flagged reports are kept but ignored. To see them:
`select * from reports where flagged order by created_at desc;`
To delete a bad report: `delete from reports where id = 123;` (works in the SQL Editor, which runs as admin.)

## 7. Reset / reseed

- **Fresh demo data only** (keep the schema): run **`seed.sql`** again. It **deletes all venues and reports** and recreates the 20 venues with reports timestamped "now".
- **Start completely over:** run **`reset.sql`** (drops everything this project created), then run steps 2.1 → 2.6 again.
- **Nuclear option:** Project Settings → General → **Delete project**, and create a new one.

## 8. How it works (short version)

- **Tables:** `venues` (admin-managed), `reports` (crowdsourced). Deleting a venue deletes its reports (`on delete cascade`).
- **`venue_summary` view:** one row per venue. Medians of pint/shot/mixer and entry fee over the recent window, majority vote for free entry (a tie counts as paid), report count, last report time, and `price_level` from the median pint. Venues with no recent reports appear with nulls. It is a `security_invoker` view, so it runs with the caller's permissions and obeys RLS.
- **`search_venues()` RPC:** filtering for the cards (max pint, music tags, free only, user age). See API_CONTRACT.md.
- **Security (RLS):** anyone can read venues, reports, settings and the summary; anyone can **insert** reports, using only the user-facing columns. Nobody can update or delete via the API. `created_at`, `flagged` and `flag_reason` are server-controlled.
- **Abuse protection** (trigger `reports_before_insert`): 5 reports per venue per device per hour, 30 per device per hour overall, timestamps forced to server time, and prices way off the venue's 7-day median (needs ≥3 reports) are stored but flagged and excluded from the averages. `device_id` comes from the browser, so this stops casual spam, not a determined attacker. That's fine for a hackathon.
- **Realtime:** `reports` is in the `supabase_realtime` publication. Clients subscribe to INSERTs and re-fetch the summary.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| Test page shows "Not configured" | Create `test-client/config.js` from `config.example.js` (or edit `CONFIG` in index.html). |
| `Invalid API key` / 401 | Wrong key, or a stray space. Use the publishable/anon key from Project Settings → API Keys. |
| Cards show "no recent price" / empty | Reports are older than `summary_window`. Re-run `seed.sql` or switch to demo mode (7 days). |
| `relation "public.venue_summary" does not exist` / `Could not find the function public.search_venues` | A migration was skipped. Re-run 0001→0005 in order. If the API still can't see it, wait ~10 s (the API refreshes its schema cache) or run `notify pgrst, 'reload schema';`. |
| `realtime: channel_error` / `timed_out` | Check step 4 (publication toggle). In **Project Settings → Realtime**, make sure public access to channels isn't disabled. Check your network/adblocker isn't blocking websockets. |
| `permission denied for table reports` on insert | You're sending a server-only column (`id`, `created_at`, `flagged`, `flag_reason`). |
| `new row violates row-level security policy` on insert | `venue_id` doesn't exist. |
| Free-tier project paused | Free projects pause after a week of inactivity. Open the dashboard and click **Restore project**. |

## Optional: Supabase CLI

The folder follows the CLI layout (`supabase/migrations`, `supabase/seed.sql`). If you later install the CLI, run this from `backend/`:

```bash
supabase init
```

```bash
supabase link --project-ref YOUR-PROJECT-REF
```

```bash
supabase db push
```

Then run `seed.sql` in the SQL Editor (or `supabase db reset` for a local stack). The dashboard SQL Editor route above is all you need for the hackathon.
