-- =============================================================================
-- 0003_security.sql  —  Row Level Security + privileges
-- Run 3rd. Safe to re-run.
--
--   venues        : public SELECT only
--   app_settings  : public SELECT only
--   reports       : public SELECT + INSERT (only the user-facing columns),
--                   no UPDATE / DELETE from clients
--
-- Grants are explicit so this works even if "automatically expose new tables"
-- was unticked when the Supabase project was created.
-- =============================================================================

alter table public.app_settings enable row level security;
alter table public.venues       enable row level security;
alter table public.reports      enable row level security;

-- ---- table privileges -------------------------------------------------------
grant usage on schema public to anon, authenticated;

revoke all on public.app_settings, public.venues, public.reports from anon, authenticated;

grant select on public.app_settings to anon, authenticated;
grant select on public.venues       to anon, authenticated;
grant select on public.reports      to anon, authenticated;

-- Clients may only supply these columns. id, created_at, flagged and
-- flag_reason are server-controlled.
grant insert (venue_id, pint_price, shot_price, mixer_price, free_entry, entry_fee, device_id)
  on public.reports to anon, authenticated;

-- ---- policies ----------------------------------------------------------------
drop policy if exists "Public can read settings" on public.app_settings;
create policy "Public can read settings"
  on public.app_settings for select
  to anon, authenticated
  using (true);

drop policy if exists "Public can read venues" on public.venues;
create policy "Public can read venues"
  on public.venues for select
  to anon, authenticated
  using (true);

drop policy if exists "Public can read reports" on public.reports;
create policy "Public can read reports"
  on public.reports for select
  to anon, authenticated
  using (true);

drop policy if exists "Public can submit reports" on public.reports;
create policy "Public can submit reports"
  on public.reports for insert
  to anon, authenticated
  with check (
    exists (select 1 from public.venues v where v.id = venue_id)
  );

-- No UPDATE or DELETE policies exist, and no UPDATE/DELETE privileges are
-- granted, so clients cannot modify or remove anything.
