-- =============================================================================
-- verify.sql  —  self-test. Paste into the SQL Editor and click Run.
-- Runs checks AS THE PUBLIC "anon" ROLE (exactly what the website uses) and
-- shows a PASS/FAIL table at the end. Cleans up all test rows afterwards.
-- Requires: migrations 0001-0005 + seed.sql already run.
-- =============================================================================

drop table if exists pg_temp.verify_results;
create temp table verify_results (
  ts     timestamptz default clock_timestamp(),
  test   text,
  result text,
  detail text
);
grant insert, select on verify_results to anon;

-- a venue with no reports, to prove empty venues still show up
insert into public.venues (name, type, music, min_age)
values ('Verify Empty Venue', 'bar', array['verifytag'], 18)
on conflict do nothing;

-- ---------------------------------------------------------------------------
set role anon;
-- ---------------------------------------------------------------------------

do $$
declare n int; m int; vid bigint; r record; ok boolean; msg text; hint text;
        dev text := 'verify-' || substr(md5(random()::text), 1, 12);
begin
  -- 1. reads ---------------------------------------------------------------
  select count(*) into n from public.venues;
  insert into verify_results(test, result, detail) values
    ('anon can read venues', case when n >= 20 then 'PASS' else 'FAIL' end, n || ' rows');

  select count(*) into n from public.reports;
  insert into verify_results(test, result, detail) values
    ('anon can read reports', case when n > 0 then 'PASS' else 'FAIL' end, n || ' rows');

  select count(*) into n from public.venue_summary;
  select count(*) into m from public.venues;
  insert into verify_results(test, result, detail) values
    ('venue_summary: one row per venue (as anon)', case when n = m and n > 0 then 'PASS' else 'FAIL' end, n || ' summary rows / ' || m || ' venues');

  select count(*) into n from public.venue_summary where report_count > 0 and median_pint_price is not null;
  insert into verify_results(test, result, detail) values
    ('venue_summary: seeded venues have recent prices', case when n >= 20 then 'PASS' else 'FAIL' end,
     n || ' venues with a median pint (0 => seed is older than summary_window; re-run seed.sql)');

  select * into r from public.venue_summary where name = 'Verify Empty Venue';
  insert into verify_results(test, result, detail) values
    ('venue_summary: venue with no reports appears with nulls',
     case when r.id is not null and r.report_count = 0 and r.median_pint_price is null and r.price_level is null
          then 'PASS' else 'FAIL' end, coalesce(row_to_json(r)::text, 'not found'));

  -- 2. search_venues ------------------------------------------------------
  select count(*) into n from public.search_venues(max_age => 18) where min_age > 18;
  select count(*) into m from public.search_venues(max_age => 18);
  insert into verify_results(test, result, detail) values
    ('search_venues(max_age=>18) hides 21+ venues', case when n = 0 and m > 0 then 'PASS' else 'FAIL' end, m || ' venues returned');

  select count(*) into n from public.search_venues(music => array['TECHNO']) where not ('techno' = any(music));
  select count(*) into m from public.search_venues(music => array['TECHNO']);
  insert into verify_results(test, result, detail) values
    ('search_venues(music=>[TECHNO]) case-insensitive tag match', case when n = 0 and m > 0 then 'PASS' else 'FAIL' end, m || ' venues returned');

  select count(*) into n from public.search_venues(max_pint => 6.00) where median_pint_price > 6.00 or median_pint_price is null;
  select count(*) into m from public.search_venues(max_pint => 6.00);
  insert into verify_results(test, result, detail) values
    ('search_venues(max_pint=>6.00)', case when n = 0 and m > 0 then 'PASS' else 'FAIL' end, m || ' venues returned');

  select count(*) into n from public.search_venues(free_only => true) where free_entry is not true;
  select count(*) into m from public.search_venues(free_only => true);
  insert into verify_results(test, result, detail) values
    ('search_venues(free_only=>true)', case when n = 0 and m > 0 then 'PASS' else 'FAIL' end, m || ' venues returned');

  -- 3. inserts ------------------------------------------------------------
  select id into vid from public.venues where name <> 'Verify Empty Venue' order by id limit 1;

  begin
    insert into public.reports (venue_id, pint_price, device_id) values (vid, 6.10, dev);
    ok := true; msg := 'inserted';
  exception when others then ok := false; msg := sqlerrm;
  end;
  insert into verify_results(test, result, detail) values
    ('anon can insert a valid report', case when ok then 'PASS' else 'FAIL' end, msg);

  begin
    insert into public.reports (venue_id, pint_price, device_id) values (vid, 150, dev || 'b');
    ok := false; msg := 'insert was allowed';
  exception when check_violation then ok := true; msg := sqlerrm;
            when others then ok := false; msg := sqlerrm;
  end;
  insert into verify_results(test, result, detail) values
    ('price > 100 rejected', case when ok then 'PASS' else 'FAIL' end, msg);

  begin
    insert into public.reports (venue_id, device_id) values (vid, dev || 'c');
    ok := false; msg := 'insert was allowed';
  exception when check_violation then ok := true; msg := sqlerrm;
            when others then ok := false; msg := sqlerrm;
  end;
  insert into verify_results(test, result, detail) values
    ('empty report rejected', case when ok then 'PASS' else 'FAIL' end, msg);

  begin
    insert into public.reports (venue_id, free_entry, entry_fee, device_id) values (vid, true, 10, dev || 'd');
    ok := false; msg := 'insert was allowed';
  exception when check_violation then ok := true; msg := sqlerrm;
            when others then ok := false; msg := sqlerrm;
  end;
  insert into verify_results(test, result, detail) values
    ('free_entry=true with a fee rejected', case when ok then 'PASS' else 'FAIL' end, msg);

  begin
    insert into public.reports (venue_id, pint_price, device_id, created_at) values (vid, 6, dev || 'e', now() - interval '1 day');
    ok := false; msg := 'insert was allowed';
  exception when insufficient_privilege then ok := true; msg := sqlerrm;
            when others then ok := false; msg := sqlerrm;
  end;
  insert into verify_results(test, result, detail) values
    ('anon cannot set created_at', case when ok then 'PASS' else 'FAIL' end, msg);

  begin
    insert into public.venues (name, type) values ('Hacker Bar', 'bar');
    ok := false; msg := 'insert was allowed';
  exception when insufficient_privilege then ok := true; msg := sqlerrm;
            when others then ok := false; msg := sqlerrm;
  end;
  insert into verify_results(test, result, detail) values
    ('anon cannot insert venues', case when ok then 'PASS' else 'FAIL' end, msg);

  -- 4. no update / delete ---------------------------------------------------
  begin
    update public.reports set pint_price = 1 where device_id = dev;
    ok := false; msg := 'update was allowed';
  exception when insufficient_privilege then ok := true; msg := sqlerrm;
            when others then ok := false; msg := sqlerrm;
  end;
  insert into verify_results(test, result, detail) values
    ('anon cannot update reports', case when ok then 'PASS' else 'FAIL' end, msg);

  begin
    delete from public.reports where device_id = dev;
    ok := false; msg := 'delete was allowed';
  exception when insufficient_privilege then ok := true; msg := sqlerrm;
            when others then ok := false; msg := sqlerrm;
  end;
  insert into verify_results(test, result, detail) values
    ('anon cannot delete reports', case when ok then 'PASS' else 'FAIL' end, msg);

  -- 5. rate limit: 1 report already sent above; send until blocked ----------
  ok := false; msg := 'never blocked';
  for i in 1..10 loop
    begin
      insert into public.reports (venue_id, mixer_price, device_id) values (vid, 4.20, dev);
    exception when others then
      get stacked diagnostics hint = pg_exception_hint;
      ok := (hint = 'rate_limited'); msg := 'blocked on report #' || (i + 1) || ': ' || sqlerrm;
      exit;
    end;
  end loop;
  insert into verify_results(test, result, detail) values
    ('rate limit per device per venue', case when ok then 'PASS' else 'FAIL' end, msg);

  -- 6. outlier flagging ----------------------------------------------------
  insert into public.reports (venue_id, pint_price, device_id) values (vid, 40, dev || 'f');
  select flagged, flag_reason into r from public.reports where device_id = dev || 'f';
  insert into verify_results(test, result, detail) values
    ('extreme pint price is flagged (ignored by summary)', case when r.flagged then 'PASS' else 'FAIL' end, coalesce(r.flag_reason, 'not flagged'));
end
$$;

-- ---------------------------------------------------------------------------
reset role;
-- ---------------------------------------------------------------------------

-- realtime publication (checked as admin)
insert into verify_results(test, result, detail)
select 'realtime enabled on reports',
       case when count(*) = 1 then 'PASS' else 'FAIL' end,
       'supabase_realtime publication'
from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reports';

-- clean up
delete from public.reports where device_id like 'verify-%';
delete from public.venues where name = 'Verify Empty Venue';

select test, result, detail from verify_results order by ts;
