-- National qualifying cut for each ranked event, so the app can show how far
-- inside or outside the projected NCAA championship field an athlete is.
--
-- cut_rank: how many athletes the championship takes (20 indoor, 22 outdoor
--           in 2026). Null on conference lists.
-- cut_mark: the mark of the athlete at cut_rank on the list, as TFRRS shows
--           it. Null while the list isn't that deep yet.
--
-- The scraper fills these in on its next run. Until this is applied it saves
-- ranks without them, and the app hides the qualifying status.

alter table public.list_ranks
  add column if not exists cut_rank int check (cut_rank > 0),
  add column if not exists cut_mark text;
