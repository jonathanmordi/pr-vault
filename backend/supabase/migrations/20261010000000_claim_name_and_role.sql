-- Two sign-up fixes.
--
-- 1. New accounts always start as athletes. handle_new_user used to copy
--    the role from the sign-up request's metadata, which the client
--    controls, so anyone could sign up as a coach. Nobody has; the role
--    only changes a profile label today, but coach features would rely on it.
-- 2. Claiming a TFRRS profile takes its name. The scraper also keeps
--    claimed names in sync with the TFRRS roster.

begin;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', 'New User'),
    'athlete'
  );
  return new;
end;
$$;

-- Same as in 20261004000000_list_ranks.sql, plus taking the TFRRS name.
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

  -- Take the TFRRS name too, so leaderboards match TFRRS rather than
  -- whatever was typed at sign-up.
  update public.profiles
     set tfrrs_athlete_id = v_target.tfrrs_athlete_id,
         gender = coalesce(v_target.gender, gender),
         full_name = v_target.full_name
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
