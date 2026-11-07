-- =============================================================================
-- 0004_venue_summary.sql  —  venue_summary view + search_venues() RPC
-- Run 4th. Safe to re-run (drops and recreates both).
--
-- The time window and the €/€€/€€€ thresholds live in public.app_settings
-- (see the top of 0001_tables.sql). Quick changes:
--   update public.app_settings set summary_window = '7 days';         -- demo mode
--   update public.app_settings set summary_window = '4 hours';        -- live mode
--   update public.app_settings set price_level_1_max = 5.80, price_level_2_max = 6.60;
-- =============================================================================

drop function if exists public.search_venues(numeric, text[], boolean, int, boolean);
drop view if exists public.venue_summary;

-- security_invoker = true  => the view runs with the caller's (anon's)
-- permissions, so the RLS policies on venues/reports/app_settings apply.
create view public.venue_summary
with (security_invoker = true)
as
select
  v.id,
  v.name,
  v.type,
  v.music,
  v.min_age,
  v.image_url,
  v.created_at,
  agg.median_pint_price,
  agg.median_shot_price,
  agg.median_mixer_price,
  agg.free_entry,
  case when agg.free_entry then 0::numeric(6,2) else agg.median_entry_fee end as entry_fee,
  agg.report_count,
  lr.last_reported,
  case
    when agg.median_pint_price is null              then null
    when agg.median_pint_price <= s.price_level_1_max then 1
    when agg.median_pint_price <= s.price_level_2_max then 2
    else 3
  end as price_level
from public.venues v
cross join public.app_settings s
left join lateral (
  select
    round((percentile_cont(0.5) within group (order by r.pint_price))::numeric,  2) as median_pint_price,
    round((percentile_cont(0.5) within group (order by r.shot_price))::numeric,  2) as median_shot_price,
    round((percentile_cont(0.5) within group (order by r.mixer_price))::numeric, 2) as median_mixer_price,
    -- majority of recent reports that said anything about entry; a tie counts as paid
    case
      when count(r.free_entry) = 0 then null
      else count(*) filter (where r.free_entry) > count(*) filter (where not r.free_entry)
    end as free_entry,
    round((percentile_cont(0.5) within group (order by r.entry_fee)
           filter (where r.entry_fee > 0))::numeric, 2) as median_entry_fee,
    count(*)::int as report_count
  from public.reports r
  where r.venue_id = v.id
    and not r.flagged
    and r.created_at > now() - s.summary_window
) agg on true
left join lateral (
  select max(r2.created_at) as last_reported      -- latest report ever, not just in the window
  from public.reports r2
  where r2.venue_id = v.id and not r2.flagged
) lr on true;

comment on view public.venue_summary is
  'One row per venue with medians of recent (app_settings.summary_window) non-flagged reports.';

grant select on public.venue_summary to anon, authenticated;

-- -----------------------------------------------------------------------------
-- search_venues — filtering for the venue cards.
--   max_pint       : only venues whose median pint <= this (null = no limit)
--   music          : venue must have at least ONE of these tags (case-insensitive; null/empty = any)
--   free_only      : only venues whose recent reports say free entry
--   max_age        : the user's age. Venues with min_age > max_age are hidden
--                    (an 18-year-old passes 18 and never sees 21+ venues). null = no limit
--   include_unpriced : when max_pint is set, also keep venues with no recent pint price
-- Returns venue_summary rows, cheapest first then most recently reported.
-- -----------------------------------------------------------------------------
create function public.search_venues(
  max_pint          numeric default null,
  music             text[]  default null,
  free_only         boolean default false,
  max_age           int     default null,
  include_unpriced  boolean default false
)
returns setof public.venue_summary
language sql
stable
set search_path = public, pg_temp
as $$
  select vs.*
  from public.venue_summary vs
  where (search_venues.max_pint is null
         or vs.median_pint_price <= search_venues.max_pint
         or (search_venues.include_unpriced and vs.median_pint_price is null))
    and (search_venues.music is null
         or cardinality(search_venues.music) = 0
         or vs.music && (select coalesce(array_agg(lower(btrim(m))), '{}') from unnest(search_venues.music) m))
    and (not coalesce(search_venues.free_only, false) or vs.free_entry is true)
    and (search_venues.max_age is null or vs.min_age <= search_venues.max_age)
  order by vs.median_pint_price asc nulls last, vs.last_reported desc nulls last, vs.name;
$$;

revoke all on function public.search_venues(numeric, text[], boolean, int, boolean) from public;
grant execute on function public.search_venues(numeric, text[], boolean, int, boolean) to anon, authenticated;

-- Helper for the frontend's music filter dropdown: every distinct tag in use.
create or replace function public.music_tags()
returns setof text
language sql
stable
set search_path = public, pg_temp
as $$
  select distinct unnest(v.music) as tag from public.venues v order by 1;
$$;

revoke all on function public.music_tags() from public;
grant execute on function public.music_tags() to anon, authenticated;
