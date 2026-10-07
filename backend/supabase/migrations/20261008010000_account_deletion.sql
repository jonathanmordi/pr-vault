-- Account deletion, from the app (delete_my_account) or by an admin with
-- the secret key (delete_account).
--
-- What goes: the login and what only the user entered (lifting maxes).
-- What stays: results scraped from TFRRS. They're public, and teammates'
-- leaderboards and rivals include them. A profile linked to TFRRS stays on
-- the team and, with its login gone, is back on unclaimed_roster(), so the
-- same athlete can claim it again later. A profile never linked to TFRRS
-- holds nothing worth keeping and is removed.

begin;

create or replace function public.delete_account(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.lifting_maxes where athlete_id = p_user;
  delete from public.profiles where id = p_user and tfrrs_athlete_id is null;
  delete from auth.users where id = p_user;
end;
$$;

-- Admin only: the secret key's service_role.
revoke execute on function public.delete_account(uuid) from public, anon, authenticated;
grant execute on function public.delete_account(uuid) to service_role;

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  perform public.delete_account(auth.uid());
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

commit;
