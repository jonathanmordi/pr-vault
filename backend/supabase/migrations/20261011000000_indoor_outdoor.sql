-- Indoor and outdoor results kept apart.
--
-- TFRRS labels every track result Indoor or Outdoor (cross country
-- distances, 8k and so on, have no label). The scraper used to drop the
-- label, so an indoor 200 and an outdoor 200 were the same event and an
-- athlete had one PR across both. Now every result has a season, and an
-- athlete has one PR per event per season.
--
-- Existing results get a season guessed from the meet name, the event and
-- the date; the next scrape replaces the guesses with TFRRS's own labels
-- and rebuilds the PRs from them.

begin;

-- ─── guess_track_season() ────────────────────────────────────────────────────
-- For rows written without a season: by the old scraper, or now.

create or replace function public.guess_track_season(p_event text, p_meet text, p_date date)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    -- Cross country races are named by distance: 8k, 6k, 5k.
    when p_event ~* '^[0-9]+(\.[0-9]+)?k$' then 'xc'
    when p_meet ilike '%indoor%' then 'indoor'
    when p_meet ilike '%outdoor%' then 'outdoor'
    when p_event in ('55 Meters', '60 Meters', '55 Hurdles', '60 Hurdles', '300 Meters',
                     '500 Meters', '600 Meters', '1000 Meters', 'Weight Throw', 'Pentathlon')
      then 'indoor'
    when p_event in ('100 Meters', '100 Hurdles', '110 Hurdles', '400 Hurdles', '10,000 Meters',
                     '3000 Steeplechase', 'Hammer', 'Discus', 'Javelin', 'Decathlon',
                     '4 x 100 Relay')
      then 'outdoor'
    -- Indoor runs December to the indoor championships in mid-March.
    when extract(month from p_date) in (11, 12, 1, 2)
      or (extract(month from p_date) = 3 and extract(day from p_date) <= 15)
      then 'indoor'
    else 'outdoor'
  end
$$;

-- ─── meet_appearances.season ─────────────────────────────────────────────────

alter table public.meet_appearances add column if not exists season text;

update public.meet_appearances
   set season = public.guess_track_season(event, meet_name, meet_date)
 where season is null;

create or replace function public.fill_appearance_season()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.season is null then
    new.season := public.guess_track_season(new.event, new.meet_name, new.meet_date);
  end if;
  return new;
end;
$$;

drop trigger if exists meet_appearances_fill_season on public.meet_appearances;
create trigger meet_appearances_fill_season
  before insert or update on public.meet_appearances
  for each row execute function public.fill_appearance_season();

alter table public.meet_appearances
  alter column season set not null,
  drop constraint if exists meet_appearances_season_check,
  add constraint meet_appearances_season_check check (season in ('indoor', 'outdoor', 'xc'));

-- ─── track_prs: one per event per season ─────────────────────────────────────

alter table public.track_prs add column if not exists season text;

alter table public.track_prs drop constraint if exists track_prs_athlete_id_event_key;

-- Every PR came from a scraped result (there are no manual ones), so the
-- PRs are rebuilt from the results: each athlete's best per event and
-- season, and how much it improved on their best before that day.
delete from public.track_prs where data_source = 'tfrrs';

with results as (
  select a.*,
         -- Higher is better: marks as they are, times negated.
         coalesce(a.mark_meters, -a.time_seconds) as score
    from public.meet_appearances a
   where coalesce(a.mark_meters, a.time_seconds) is not null
),
best as (
  select distinct on (athlete_id, event, season) *
    from results
   order by athlete_id, event, season, score desc, meet_date asc
),
with_previous as (
  select b.*,
         (select max(r.score)
            from results r
           where r.athlete_id = b.athlete_id
             and r.event = b.event
             and r.season = b.season
             and r.meet_date < b.meet_date) as previous_score
    from best b
)
insert into public.track_prs (
  team_id, athlete_id, event, season, best_time_seconds, best_mark_meters, best_display,
  set_on, set_at_meet, previous_best_seconds, improvement_delta_pct, data_source
)
select team_id, athlete_id, event, season, time_seconds, mark_meters, display_value,
       meet_date, meet_name,
       case when time_seconds is not null then -previous_score end,
       case
         when previous_score is null or previous_score = 0 then 0
         when mark_meters is not null
           then round(((score - previous_score) / previous_score * 100)::numeric, 4)
         else round(((-previous_score - time_seconds) / -previous_score * 100)::numeric, 4)
       end,
       'tfrrs'
  from with_previous;

create or replace function public.fill_pr_season()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.season is null then
    new.season := public.guess_track_season(new.event, new.set_at_meet, new.set_on);
  end if;
  return new;
end;
$$;

drop trigger if exists track_prs_fill_season on public.track_prs;
create trigger track_prs_fill_season
  before insert or update on public.track_prs
  for each row execute function public.fill_pr_season();

alter table public.track_prs
  alter column season set not null,
  drop constraint if exists track_prs_season_check,
  add constraint track_prs_season_check check (season in ('indoor', 'outdoor', 'xc')),
  drop constraint if exists track_prs_athlete_id_event_season_key,
  add constraint track_prs_athlete_id_event_season_key unique (athlete_id, event, season);

commit;
