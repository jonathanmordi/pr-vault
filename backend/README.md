# Backend

Supabase database migrations live in `supabase/migrations/`, applied in filename order.

## Applying

With the [Supabase CLI](https://supabase.com/docs/guides/cli), from this directory:

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

Or paste a migration file into the dashboard's SQL editor and run it.

## Access model

- Every signed-in user can read only their own team's `teams`, `profiles`,
  `track_prs`, `meet_appearances`, `school_records` and `lifting_maxes`.
- Clients can write only their own `full_name` and their own `lifting_maxes`.
- Joining a team (`join_team`) and claiming a scraped TFRRS profile
  (`claim_tfrrs_profile`) go through `SECURITY DEFINER` functions that
  validate the request server-side.
- The anon role has no table access.
- The scraper uses the secret key, which bypasses RLS.
