-- Team-scoped Row Level Security.
--
-- Every signed-in user can only see data belonging to their own team, and can
-- only write the few things the app legitimately lets them write (their own
-- name and their own lifting maxes). Everything that used to be a raw
-- cross-row write from the client (joining a team, claiming a scraped TFRRS
-- profile) now goes through a SECURITY DEFINER function that validates the
-- request server-side.
--
-- The scraper uses the secret (service role) key, which bypasses RLS, so it is
-- unaffected by anything here.
--
-- This migration is the source of truth for policies on these tables: it drops
-- every existing policy on them first, so a leftover permissive policy (e.g.
-- the dashboard's "Enable read access for all users") can't silently OR
-- itself back in.

begin;

-- ─── Drop existing policies ──────────────────────────────────────────────────

do $$
declare
  pol record;
begin
  for pol in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('teams', 'profiles', 'track_prs', 'meet_appearances',
                        'school_records', 'lifting_maxes')
  loop
    execute format('drop policy %I on %I.%I',
                   pol.policyname, pol.schemaname, pol.tablename);
  end loop;
end $$;

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- SECURITY DEFINER so policies on profiles can call it without recursing
-- into profiles' own RLS.
create or replace function public.my_team_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select team_id from public.profiles where id = auth.uid();
$$;

revoke execute on function public.my_team_id() from public, anon;
grant execute on function public.my_team_id() to authenticated;

-- ─── Enable RLS ──────────────────────────────────────────────────────────────

alter table public.teams            enable row level security;
alter table public.profiles         enable row level security;
alter table public.track_prs        enable row level security;
alter table public.meet_appearances enable row level security;
alter table public.school_records   enable row level security;
alter table public.lifting_maxes    enable row level security;

-- ─── Table privileges ────────────────────────────────────────────────────────
-- Defense in depth: even if a policy is later added by mistake, the anon role
-- and client writes to scraper-owned tables stay blocked at the grant level.

revoke all on public.teams, public.profiles, public.track_prs,
              public.meet_appearances, public.school_records,
              public.lifting_maxes
  from anon;

revoke insert, update, delete on public.teams, public.track_prs,
                                 public.meet_appearances,
                                 public.school_records
  from authenticated;

-- Users may only ever change their own display name directly. team_id, role,
-- gender and tfrrs_athlete_id are set by join_team / claim_tfrrs_profile.
revoke update, delete on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;

-- ─── teams ───────────────────────────────────────────────────────────────────

create policy "teams: members read own team"
  on public.teams for select to authenticated
  using (id = public.my_team_id());

-- ─── profiles ────────────────────────────────────────────────────────────────

create policy "profiles: read self and teammates"
  on public.profiles for select to authenticated
  using (id = auth.uid() or team_id = public.my_team_id());

-- A new user may create only their own row, teamless, as an athlete.
create policy "profiles: create own row"
  on public.profiles for insert to authenticated
  with check (id = auth.uid() and team_id is null and role = 'athlete');

create policy "profiles: update own row"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ─── Scraper-owned, read-only to clients ─────────────────────────────────────

create policy "track_prs: read own team"
  on public.track_prs for select to authenticated
  using (team_id = public.my_team_id());

create policy "meet_appearances: read own team"
  on public.meet_appearances for select to authenticated
  using (team_id = public.my_team_id());

create policy "school_records: read own team"
  on public.school_records for select to authenticated
  using (team_id = public.my_team_id());

-- ─── lifting_maxes ───────────────────────────────────────────────────────────

create policy "lifting_maxes: read own team"
  on public.lifting_maxes for select to authenticated
  using (team_id = public.my_team_id());

create policy "lifting_maxes: insert own"
  on public.lifting_maxes for insert to authenticated
  with check (athlete_id = auth.uid() and team_id = public.my_team_id());

create policy "lifting_maxes: update own"
  on public.lifting_maxes for update to authenticated
  using (athlete_id = auth.uid())
  with check (athlete_id = auth.uid() and team_id = public.my_team_id());

create policy "lifting_maxes: delete own"
  on public.lifting_maxes for delete to authenticated
  using (athlete_id = auth.uid());

-- ─── join_team(code) ─────────────────────────────────────────────────────────
-- Replaces the client reading `teams` by invite code (which RLS now hides from
-- teamless users) and then writing its own team_id. Creates the caller's
-- profile if it doesn't exist yet. Returns {id, name} of the team, or null for
-- an unknown code. A user already on a team can't hop to another one.

create or replace function public.join_team(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_team    public.teams%rowtype;
  v_current uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v_team
  from public.teams
  where upper(invite_code) = upper(trim(p_code));

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

revoke execute on function public.join_team(text) from public, anon;
grant execute on function public.join_team(text) to authenticated;

-- ─── claim_tfrrs_profile(profile_id) ─────────────────────────────────────────
-- Replaces the client-side linking flow, which needed to rewrite other
-- athletes' track_prs / meet_appearances rows and delete their profile. Now a
-- single transaction, and only allowed when:
--   * the target is a scraper-created profile (not a real user's account),
--   * it's on the caller's team, and
--   * the caller hasn't already claimed a TFRRS profile.

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

  delete from public.profiles where id = v_target.id;
end;
$$;

revoke execute on function public.claim_tfrrs_profile(uuid) from public, anon;
grant execute on function public.claim_tfrrs_profile(uuid) to authenticated;

commit;
