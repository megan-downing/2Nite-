-- =============================================================================
-- seed.sql  —  20 fictional Cork-style venues + 3-10 recent reports each
-- Run AFTER all migrations. Re-running WIPES all venues and reports and
-- re-creates fresh demo data (timestamps are relative to now()).
-- Venue names are made up; images are placeholders from picsum.photos.
-- =============================================================================

truncate table public.reports, public.venues restart identity cascade;

insert into public.venues (name, type, music, min_age, image_url) values
  ('The Lee Lantern',        'bar',  array['trad','folk'],              18, 'https://picsum.photos/seed/lee-lantern/640/400'),
  ('Quayside Social',        'bar',  array['indie','pop'],              18, 'https://picsum.photos/seed/quayside-social/640/400'),
  ('Mardyke Mill',           'club', array['techno','house'],           21, 'https://picsum.photos/seed/mardyke-mill/640/400'),
  ('The Red Abbey Arms',     'bar',  array['rock','indie'],             18, 'https://picsum.photos/seed/red-abbey-arms/640/400'),
  ('Basement Nine',          'club', array['techno'],                   21, 'https://picsum.photos/seed/basement-nine/640/400'),
  ('The Copper Kettle',      'bar',  array['trad'],                     18, 'https://picsum.photos/seed/copper-kettle/640/400'),
  ('Neon Harbour',           'club', array['pop','hip-hop'],            18, 'https://picsum.photos/seed/neon-harbour/640/400'),
  ('The Stitch & Barrel',    'bar',  array['indie','folk'],             18, 'https://picsum.photos/seed/stitch-barrel/640/400'),
  ('Gallows Lane',           'club', array['house','disco'],            21, 'https://picsum.photos/seed/gallows-lane/640/400'),
  ('The Tidal Room',         'bar',  array['jazz','soul'],              18, 'https://picsum.photos/seed/tidal-room/640/400'),
  ('Stormgate',              'club', array['rock','metal'],             18, 'https://picsum.photos/seed/stormgate/640/400'),
  ('Pulse Warehouse',        'club', array['techno','house'],           21, 'https://picsum.photos/seed/pulse-warehouse/640/400'),
  ('The Fiddler''s Rest',    'bar',  array['trad','folk'],              18, 'https://picsum.photos/seed/fiddlers-rest/640/400'),
  ('Velvet Fox Lounge',      'bar',  array['pop','r&b'],                21, 'https://picsum.photos/seed/velvet-fox/640/400'),
  ('Grand Parade Taproom',   'bar',  array['rock','indie'],             18, 'https://picsum.photos/seed/grand-parade-taproom/640/400'),
  ('Bassline',               'club', array['hip-hop','drum-and-bass'],  18, 'https://picsum.photos/seed/bassline/640/400'),
  ('The Weighhouse',         'bar',  array['trad','pop'],               18, 'https://picsum.photos/seed/weighhouse/640/400'),
  ('Skyline Rooftop',        'bar',  array['house','pop'],              21, 'https://picsum.photos/seed/skyline-rooftop/640/400'),
  ('Afterglow',              'club', array['pop','house'],              18, 'https://picsum.photos/seed/afterglow/640/400'),
  ('The Riverside Snug',     'bar',  array['trad','folk','rock'],       18, 'https://picsum.photos/seed/riverside-snug/640/400');

-- Typical prices per venue; individual reports vary around these.
-- fee = typical club entry (0 = free). n = number of seed reports (3-10).
select setseed(0.42);  -- same "random" data every time

insert into public.reports
  (venue_id, pint_price, shot_price, mixer_price, free_entry, entry_fee, device_id, created_at)
select
  v.id,
  case when g % 4 <> 0 then round((p.pint  + (random() - 0.5) * 0.6) * 10) / 10 end,
  case when g % 2 = 0  then round((p.shot  + (random() - 0.5) * 0.6) * 10) / 10 end,
  case when g % 3 <> 1 then round((p.mixer + (random() - 0.5) * 0.4) * 10) / 10 end,
  -- clubs usually report entry, bars occasionally (always free)
  case
    when v.type = 'club' and g % 3 <> 2 then p.fee = 0
    when v.type = 'bar'  and g % 3 = 0  then true
  end,
  case
    when v.type = 'club' and g % 3 <> 2 then p.fee + case when p.fee > 0 and g % 5 = 0 then 2 else 0 end
    when v.type = 'bar'  and g % 3 = 0  then 0
  end,
  'seed-' || v.id || '-' || g,
  now() - make_interval(mins => (5 + random() * 225)::int)   -- within the last ~4 hours
from public.venues v
join (values
  ('The Lee Lantern',       5.60, 4.20, 3.60,  0,  6),
  ('Quayside Social',       6.20, 4.80, 4.20,  0,  8),
  ('Mardyke Mill',          7.20, 5.80, 4.90, 15, 10),
  ('The Red Abbey Arms',    5.80, 4.50, 3.80,  0,  5),
  ('Basement Nine',         7.00, 5.50, 4.80, 12,  7),
  ('The Copper Kettle',     5.50, 4.00, 3.50,  0,  3),
  ('Neon Harbour',          6.90, 5.00, 4.50,  0,  9),
  ('The Stitch & Barrel',   6.40, 4.80, 4.20,  0,  4),
  ('Gallows Lane',          7.40, 6.00, 5.00, 10,  6),
  ('The Tidal Room',        6.60, 5.20, 4.60,  0,  3),
  ('Stormgate',             6.30, 4.50, 4.00,  5,  5),
  ('Pulse Warehouse',       7.50, 6.00, 5.00, 15,  8),
  ('The Fiddler''s Rest',   5.70, 4.30, 3.70,  0,  6),
  ('Velvet Fox Lounge',     7.10, 5.60, 4.90,  0,  4),
  ('Grand Parade Taproom',  6.00, 4.60, 4.00,  0,  7),
  ('Bassline',              6.50, 4.50, 4.20,  8,  9),
  ('The Weighhouse',        5.90, 4.40, 3.90,  0,  3),
  ('Skyline Rooftop',       7.30, 5.90, 5.00,  0,  5),
  ('Afterglow',             6.70, 5.00, 4.50,  5, 10),
  ('The Riverside Snug',    5.60, 4.20, 3.60,  0,  4)
) as p(name, pint, shot, mixer, fee, n) on p.name = v.name
cross join lateral generate_series(1, p.n) as g;

-- Show what was created
select name, type, price_level, median_pint_price, free_entry, entry_fee, report_count
from public.venue_summary order by name;
