# Backend

Supabase database migrations live in `supabase/migrations/`, applied in filename order.

## Applying

With the [Supabase CLI](https://supabase.com/docs/guides/cli), from this directory:

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

Or paste a migration file into the dashboard's SQL editor and run it.

`supabase/config.toml` mirrors the live project's settings (pulled with
`supabase config pull`). `supabase config push` only writes what the file
declares, so settings made in the dashboard, like SMTP, are left alone.
Preview with `supabase config diff` first.

## Access model

- Every signed-in user can read only their own team's `teams`, `profiles`,
  `track_prs`, `meet_appearances`, `school_records`, `lifting_maxes` and
  `list_ranks`.
- Clients can write only their own `full_name` and their own `lifting_maxes`.
- Joining a team and claiming a scraped TFRRS profile go through
  `SECURITY DEFINER` functions that validate the request server-side:
  `join_team_by_email` (only for emails verified with an emailed code),
  `join_team` (invite code fallback), `unclaimed_roster` and
  `claim_tfrrs_profile`.
- `delete_my_account` deletes the caller's login and lifting maxes. A
  profile linked to TFRRS stays on the team with its results and becomes
  claimable again; an unlinked profile is removed.
- The anon role has no table access.
- The scraper uses the secret key, which bypasses RLS.

## Deleting an account by hand

With the secret key (same steps as `delete_my_account`):

```bash
curl -X POST "$SUPABASE_URL/rest/v1/rpc/delete_account" \
  -H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" -d '{"p_user": "<user id>"}'
```
