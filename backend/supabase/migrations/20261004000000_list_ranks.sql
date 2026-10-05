-- National and conference performance-list ranks, scraped from TFRRS.
--
-- One row per athlete, event, list scope and season. TFRRS lists rank each
-- athlete's season best, so a rank always belongs to a season. The scraper
-- (service role, bypasses RLS) rewrites a season's rows on every run;
-- team members can only read their own team's rows.

begin;

create table if not exists public.list_ranks (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid not null references public.teams (id) on delete cascade,
  athlete_id   uuid not null references public.profiles (id) on delete cascade,
  event        text not null,
  scope        text not null check (scope in ('national', 'conference')),
  -- Short display name for the list, e.g. 'D3' or 'MAC'.
  label        text not null,
  season       text not null check (season in ('indoor', 'outdoor')),
  season_year  int  not null,
  rank         int  not null check (rank > 0),
  -- How many athletes the scraped list holds, so "#480 of 500" reads right.
  list_size    int  not null,
  mark_display text,
  list_name    text not null,
  list_url     text not null,
  updated_at   timestamptz not null default now(),
  unique (athlete_id, event, scope, season, season_year)
);

create index if not exists list_ranks_team_idx on public.list_ranks (team_id);

alter table public.list_ranks enable row level security;

revoke all on public.list_ranks from anon;
revoke insert, update, delete on public.list_ranks from authenticated;

drop policy if exists "list_ranks: read own team" on public.list_ranks;
create policy "list_ranks: read own team"
  on public.list_ranks for select to authenticated
  using (team_id = public.my_team_id());

-- ─── claim_tfrrs_profile(profile_id) ─────────────────────────────────────────
-- Same as in 20260924000000_team_scoped_rls.sql, plus moving list_ranks.
-- Without that, ranks would cascade-delete with the scraped profile and stay
-- missing until the next nightly scrape.

create or replace function public.claim_tfrrs_profile(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_me     public.profiles%rowtype;
  v_target public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v_me from public.profiles where id = v_uid;
  if not found or v_me.team_id is null then
    raise exception 'join a team before linking a TFRRS profile';
  end if;
  if v_me.tfrrs_athlete_id is not null then
    raise exception 'you have already linked a TFRRS profile';
  end if;

  select * into v_target from public.profiles where id = p_profile_id for update;
  if not found
     or v_target.tfrrs_athlete_id is null
     or v_target.team_id is distinct from v_me.team_id then
    raise exception 'profile not found';
  end if;
  if exists (select 1 from auth.users where id = p_profile_id) then
    raise exception 'that profile has already been claimed';
  end if;

  -- Free the TFRRS id first in case tfrrs_athlete_id is unique.
  update public.profiles set tfrrs_athlete_id = null where id = v_target.id;

  update public.profiles
     set tfrrs_athlete_id = v_target.tfrrs_athlete_id,
         gender = coalesce(v_target.gender, gender)
   where id = v_uid;

  update public.track_prs        set athlete_id = v_uid where athlete_id = v_target.id;
  update public.meet_appearances set athlete_id = v_uid where athlete_id = v_target.id;
  update public.lifting_maxes    set athlete_id = v_uid where athlete_id = v_target.id;
  update public.list_ranks       set athlete_id = v_uid where athlete_id = v_target.id;

  delete from public.profiles where id = v_target.id;
end;
$$;

revoke execute on function public.claim_tfrrs_profile(uuid) from public, anon;
grant execute on function public.claim_tfrrs_profile(uuid) to authenticated;

commit;
