-- Who's still on the team. The scraper reads the current TFRRS roster every
-- night: athletes on it are on_roster with their class year; athletes who
-- drop off it (graduated, transferred, quit) become alumni, dated by when
-- they were first missing. Alumni keep their profiles, results and logins.
-- Clients can't write these columns (only full_name, see team_scoped_rls).

begin;

alter table public.profiles
  add column if not exists on_roster boolean not null default true,
  add column if not exists left_roster_on date,
  -- As TFRRS shows it: 'FR-1', 'SO-2', 'JR-3', 'SR-4'.
  add column if not exists class_year text;

-- unclaimed_roster(): now also says who's current, so "Which one is you?"
-- can list the current roster first and alumni after. Changing the result
-- columns means dropping the old function.

drop function if exists public.unclaimed_roster();

create function public.unclaimed_roster()
returns table (id uuid, full_name text, gender text, on_roster boolean, class_year text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.full_name, p.gender, p.on_roster, p.class_year
  from public.profiles p
  where p.team_id = public.my_team_id()
    and p.tfrrs_athlete_id is not null
    and not exists (select 1 from auth.users u where u.id = p.id)
  order by p.on_roster desc, p.full_name;
$$;

revoke execute on function public.unclaimed_roster() from public, anon;
grant execute on function public.unclaimed_roster() to authenticated;

commit;
