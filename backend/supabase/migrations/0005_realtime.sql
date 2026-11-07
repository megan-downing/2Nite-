-- =============================================================================
-- 0005_realtime.sql  —  broadcast new reports via Supabase Realtime
-- Run 5th. Safe to re-run.
--
-- Realtime only sends changes for tables in the "supabase_realtime"
-- publication. Realtime respects RLS, and anon may SELECT reports, so the
-- website receives INSERT events. (Same as toggling "Enable Realtime" on the
-- reports table in the dashboard.)
-- =============================================================================

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reports'
  ) then
    alter publication supabase_realtime add table public.reports;
  end if;
end
$$;
