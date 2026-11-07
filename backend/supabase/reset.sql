-- =============================================================================
-- reset.sql  —  DELETE EVERYTHING this project created (tables, data, view,
-- functions, trigger, realtime entry). Then re-run migrations 0001-0005 and
-- seed.sql to start fresh.
--
-- To only refresh the demo DATA (keep the schema), just re-run seed.sql.
-- =============================================================================

do $$
begin
  if exists (select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reports') then
    alter publication supabase_realtime drop table public.reports;
  end if;
end
$$;

drop function if exists public.search_venues(numeric, text[], boolean, int, boolean);
drop function if exists public.music_tags();
drop view     if exists public.venue_summary;
drop table    if exists public.reports;
drop table    if exists public.venues;
drop table    if exists public.app_settings;
drop function if exists public.reports_before_insert();
