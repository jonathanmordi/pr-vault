-- Self-serve sign-up: verify a school email to join that school's team, then
-- claim your scraped TFRRS profile. Invite codes (join_team) stay as a
-- fallback for people without a school email.

begin;

-- ─── teams.email_domain ──────────────────────────────────────────────────────
-- The school email domain that admits people to the team, e.g. 'stevens.edu'.

alter table public.teams
  add column if not exists email_domain text;

create unique index if not exists teams_email_domain_key
  on public.teams (lower(email_domain));

update public.teams
   set email_domain = 'stevens.edu'
 where school = 'Stevens' and email_domain is null;

-- ─── join_team_by_email() ────────────────────────────────────────────────────
-- Joins the team whose email_domain matches the caller's email. Only emails
-- verified with a code we actually sent count (confirmation_sent_at): while
-- email confirmation is off, new accounts are auto-confirmed without any
-- email, and those must not get onto a team by domain alone.
-- Returns {id, name} of the team, or null if no team uses the domain.

create or replace function public.join_team_by_email()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_email     text;
  v_confirmed timestamptz;
  v_sent      timestamptz;
  v_team      public.teams%rowtype;
  v_current   uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select u.email, u.email_confirmed_at, u.confirmation_sent_at
    into v_email, v_confirmed, v_sent
  from auth.users u
  where u.id = v_uid;

  if v_confirmed is null or v_sent is null then
    raise exception 'verify your email first';
  end if;

  select * into v_team
  from public.teams
  where lower(email_domain) = lower(split_part(v_email, '@', 2));

  if not found then
    return null;
  end if;

  select team_id into v_current from public.profiles where id = v_uid;

  if v_current is not null and v_current <> v_team.id then
    raise exception 'already on a team';
  end if;

  insert into public.profiles (id, full_name, role, team_id)
  select v_uid,
         coalesce(u.raw_user_meta_data ->> 'full_name', split_part(u.email, '@', 1)),
         'athlete',
         v_team.id
  from auth.users u
  where u.id = v_uid
  on conflict (id) do update set team_id = excluded.team_id;

  return jsonb_build_object('id', v_team.id, 'name', v_team.name);
end;
$$;

revoke execute on function public.join_team_by_email() from public, anon;
grant execute on function public.join_team_by_email() to authenticated;

-- ─── unclaimed_roster() ──────────────────────────────────────────────────────
-- Scraped TFRRS profiles on the caller's team that nobody has claimed yet,
-- for the "Which one is you?" step. Claimed profiles belong to a login, which
-- the app can't see, hence a security definer function.

create or replace function public.unclaimed_roster()
returns table (id uuid, full_name text, gender text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.full_name, p.gender
  from public.profiles p
  where p.team_id = public.my_team_id()
    and p.tfrrs_athlete_id is not null
    and not exists (select 1 from auth.users u where u.id = p.id)
  order by p.full_name;
$$;

revoke execute on function public.unclaimed_roster() from public, anon;
grant execute on function public.unclaimed_roster() to authenticated;

commit;
