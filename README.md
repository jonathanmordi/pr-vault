# PR Vault

**Track. Lift. Compete.**

A mobile app for college and high school track & field programs. PR Vault automates athlete performance tracking, gamifies team culture through improvement-based leaderboards, and bridges the gap between official meet results and weight room data.

---

## What it does

Most track stats platforms are public databases: they show raw times but offer nothing for team culture, internal competition, or coaching analytics. PR Vault is built for the team, not the public.

**Results, automatically**
- Scrapes every athlete's results from TFRRS nightly via GitHub Actions. No manual entry for track PRs.
- Indoor, outdoor and cross country are kept separate: one PR per event per season, labeled the way TFRRS labels them.
- School records, NCAA D3 and conference list ranks, and a nationals watch (inside the projected field, or how far from the cut).

**Leaderboards**
- **Heat Map**: ranks athletes by improvement percentage, not raw speed. A walk-on who drops 3% is ranked above a star who hasn't improved. That's the culture shift.
- **PR Rankings**: best marks, filtered by event group (Sprints, Mid, Hurdles, Jumps, Throws).
- **Trending**: most PRs, or season points, over the last 30 days, a season, or all time.
- One "Outdoor · All" pill switches season and gender.

**Athlete profiles**
- Tap anyone for a card; drag it up for the full profile.
- Insights worked out from the athlete's results: fresh PRs, trends, PR droughts, pace against last season, distance from school records and the nationals cut, and the closest rival.
- Progression chart, PRs with list ranks and school-record gaps, rivals, lifting maxes, and meet history.

**Team**
- Activity feed of teammates' PRs, with rival and school-record tags and an unread badge.
- Lifting maxes logged in the app.
- Alumni keep their results but leave rivals and the current leaderboards.

**Getting in**
- Sign up with a school email (verified with an emailed code) to join that school's team, then pick yourself from the TFRRS roster to bring in your results. An invite code is the fallback.
- A short how-it-works intro with live demos, replayable from Settings.
- Opens instantly: the team's data is saved on the phone, refreshed in the background, and still there offline.

**Multi-tenant**: row-level security scopes every table to the viewer's team, so each school's data is isolated. Scraping more than one team is next.

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter (iOS + Android) |
| Backend | Supabase (Postgres, Auth, PostgREST) |
| Auth | Email + password, school email verified with a 6-digit code |
| Scraper | Python + Playwright |
| Automation | GitHub Actions (nightly cron) |
| Database | PostgreSQL with Row Level Security |

---

## Architecture

```
TFRRS (public meet results, rosters, performance lists)
    ↓
Python scraper (Playwright), nightly via GitHub Actions
    ↓ secret key
Supabase Postgres (row-level security per team)
    ↓ REST, with the user's session
Flutter app, which keeps a copy of the team's data on the phone
```

**Schema:**
- `teams`: one row per school/program, with its school email domain and an invite code
- `profiles`: athletes and coaches; scraped TFRRS profiles are claimed by the athlete's login. Tracks roster status and class year
- `meet_appearances`: every result ever scraped, with its season (`indoor`, `outdoor`, `xc`)
- `track_prs`: one row per athlete, event and season: the best result and how much it improved
- `school_records`: indoor and outdoor records per event and gender
- `list_ranks`: national and conference list places, with the nationals cut
- `lifting_maxes`: entered in the app

**Scraper logic:** for each athlete, read their whole TFRRS event history (each table is labeled Indoor or Outdoor), save every result, and work out their PRs per event and season from it, so PRs never go stale. Improvement is measured against the best mark before that day, so a final isn't counted as a PR over the same day's prelim. A PR that beats the school record for its season updates the record. The scraper also reads the rosters (who's still on the team) and the D3 and conference performance lists.

---

## Project structure

```
prvault/
├── mobile_app/                  # Flutter app
│   ├── lib/
│   │   ├── main.dart            # app, auth gate, tab bar
│   │   ├── login_screen.dart
│   │   ├── onboarding.dart      # school email, team, claim your TFRRS profile
│   │   ├── intro.dart           # how-it-works intro
│   │   ├── leaderboard_screen.dart
│   │   ├── athlete_profile_screen.dart
│   │   ├── profile_screen.dart
│   │   ├── activity_screen.dart
│   │   ├── maxes_screen.dart
│   │   ├── settings_screen.dart
│   │   ├── team_data.dart       # loads the team, keeps it in memory
│   │   ├── team_cache*.dart     # the copy saved on the phone
│   │   ├── pr_stats.dart        # PRs, seasons, trends, rivals, ranks
│   │   ├── insights.dart        # rule-based athlete insights
│   │   ├── prefs.dart           # settings
│   │   └── design_system.dart   # colors, components, animations
│   ├── assets/brand/            # app icon used in the app
│   └── test/
├── scraper/                     # Python TFRRS scraper
│   ├── scraper.py
│   └── test_scraper.py
├── backend/
│   ├── README.md                # migrations and the access model
│   └── supabase/                # config, email templates, migrations
└── .github/workflows/
    └── scrape.yml               # nightly scrape at 2am UTC
```

---

## Running locally

**Flutter app:**
```bash
cd mobile_app
flutter pub get
# create lib/app_config.dart with your Supabase credentials (see below)
flutter run
flutter test
```

**Scraper:**
```bash
cd scraper
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
playwright install chromium
# create .env with SUPABASE_URL and SUPABASE_KEY
python3 scraper.py                # full scrape: rosters, athletes, list ranks
python3 scraper.py --roster-only  # just update who's on the roster
python3 scraper.py --ranks-only   # just refresh national/conference list ranks
python3 scraper.py --dry-run      # print list ranks without saving anything
pip install -r requirements-dev.txt
python3 -m pytest                 # parsing and PR logic tests
```

**Database:** migrations live in `backend/supabase/migrations/`; see [backend/README.md](backend/README.md) for applying them and the access model.

---

## Environment variables

**Flutter**: create `mobile_app/lib/app_config.dart` (gitignored):
```dart
class AppConfig {
  static const supabaseUrl = 'YOUR_SUPABASE_URL';
  static const supabaseAnonKey = 'YOUR_PUBLISHABLE_KEY';
}
```

**Scraper**: create `scraper/.env` (gitignored):
```
SUPABASE_URL=your_url
SUPABASE_KEY=your_secret_key
```

**GitHub Actions**: add as repository secrets:
- `SUPABASE_URL`
- `SUPABASE_KEY`

---

## Roadmap

- [x] Supabase schema, auth and team-scoped row-level security
- [x] Python scraper: rosters, full event histories, school records
- [x] GitHub Actions: nightly automated scraping
- [x] Heat Map, PR Rankings and Trending leaderboards
- [x] Indoor, outdoor and cross country kept separate
- [x] NCAA D3 and conference list ranks, nationals watch
- [x] Athlete profiles: insights, progression, rivals, meet history
- [x] Activity feed with rivals and an unread badge
- [x] Lifting maxes
- [x] Sign-up with a verified school email, claim your TFRRS profile
- [x] Women's team, alumni, account deletion
- [x] Design system, dark mode, app icon, how-it-works intro
- [x] Instant open and offline viewing
- [ ] More teams: scrape every team in the database, not just one
- [ ] Goals: a target per event, with progress on your profile
- [ ] Share a PR as an image
- [ ] Reactions and comments on PRs
- [ ] AI-written insights
- [ ] Push notifications for PRs
- [ ] Season report: PDF export for coaches
- [ ] App Store submission

---

## Pricing

| Tier | Price | Target |
|------|-------|--------|
| Starter | $499/yr | Small programs, JV |
| Program | $1,199/yr | Full D3 program |
| Elite | $2,499/yr | D1/D2, multiple sports |

---

## Built by

Jonathan Mordi, CS freshman at Stevens Institute of Technology, D3 triple/long/high jumper.

Built this because the tools didn't exist. Using it on my own team first.

---

*PR Vault is not affiliated with TFRRS or DirectAthletics.*
