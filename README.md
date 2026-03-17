# PR Vault

**Track. Lift. Compete.**

A mobile SaaS platform for college and high school track & field programs. PR Vault automates athlete performance tracking, gamifies team culture through improvement-based leaderboards, and bridges the gap between official meet results and weight room data.

---

## What it does

Most track stats platforms are public databases — they show raw times but offer nothing for team culture, internal competition, or coaching analytics. PR Vault is built for the team, not the public.

- **Automated data** — scrapes official meet results from TFRRS nightly via GitHub Actions. No manual entry for track PRs.
- **Heat Map leaderboard** — ranks athletes by improvement percentage, not raw speed. A walk-on who drops 3% is ranked above a star who hasn't improved. That's the culture shift.
- **PR Rankings** — traditional fastest-first leaderboard with event filtering by category (Sprints, Mid, Hurdles, Jumps, Throws).
- **Athlete profiles** — personal PR cards with stat grids, improvement tracking, and meet history.
- **Multi-tenant** — each school's data is fully isolated. Built for scale from day one.

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter (iOS + Android) |
| Backend | Supabase (Postgres, Auth, Realtime) |
| Scraper | Python + Playwright |
| Automation | GitHub Actions (nightly cron) |
| Database | PostgreSQL with Row Level Security |

---

## Architecture

```
TFRRS (public meet results)
    ↓
Python scraper (Playwright)
    ↓ runs nightly via GitHub Actions
Supabase Postgres
    ↓ Realtime subscriptions
Flutter app (iOS + Android)
```

**Schema:**
- `teams` — one row per school/program
- `profiles` — extends Supabase auth, linked to a team via invite code
- `track_prs` — one row per athlete per event, always the best result
- `meet_appearances` — every result ever scraped, full history log

**Scraper logic:** for every result, always write to `meet_appearances`. Only update `track_prs` if the new time is faster than the existing PR. Calculate improvement delta percentage on every PR update so leaderboard queries stay fast.

---

## Project structure

```
pr-vault/
├── mobile_app/          # Flutter app
│   └── lib/
│       ├── main.dart
│       ├── design_system.dart
│       ├── leaderboard_screen.dart
│       ├── profile_screen.dart
│       └── settings_screen.dart
├── scraper/             # Python TFRRS scraper
│   ├── scraper.py
│   └── requirements.txt
├── backend/             # Supabase edge functions (future)
└── .github/
    └── workflows/
        └── scrape.yml   # Nightly GitHub Actions cron
```

---

## Running locally

**Flutter app:**
```bash
cd mobile_app
flutter pub get
# create lib/app_config.dart with your Supabase credentials
flutter run
```

**Scraper:**
```bash
cd scraper
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
playwright install chromium
# create .env with SUPABASE_URL and SUPABASE_KEY
python3 scraper.py
```

---

## Environment variables

**Flutter** — create `mobile_app/lib/app_config.dart` (gitignored):
```dart
class AppConfig {
  static const supabaseUrl = 'YOUR_SUPABASE_URL';
  static const supabaseAnonKey = 'YOUR_PUBLISHABLE_KEY';
}
```

**Scraper** — create `scraper/.env` (gitignored):
```
SUPABASE_URL=your_url
SUPABASE_KEY=your_secret_key
```

**GitHub Actions** — add as repository secrets:
- `SUPABASE_URL`
- `SUPABASE_KEY`

---

## Roadmap

- [x] Supabase schema — teams, profiles, track_prs, meet_appearances
- [x] Flutter auth — login, session management, AuthGate
- [x] Python scraper — TFRRS roster + PR upsert logic
- [x] Heat Map leaderboard — improvement % ranking
- [x] PR Rankings — raw performance sorting, field event support
- [x] GitHub Actions — nightly automated scraping
- [x] Design system — brand colors, dark mode, animations
- [x] Floating bottom nav — iOS-style navigation
- [ ] Onboarding — invite code signup flow
- [ ] Athlete profiles — full PR history + meet timeline
- [ ] Lifting entry — manual squat/bench/clean logging
- [ ] Push notifications — PR drop alerts
- [ ] RLS hardening — team-scoped policies for multi-tenant
- [ ] Season report — PDF export for coaches
- [ ] Women's team support
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

Jonathan Mordi — CS freshman at Stevens Institute of Technology, D3 triple/long/high jumper.

Built this because the tools didn't exist. Using it on my own team first.

---

*PR Vault is not affiliated with TFRRS or DirectAthletics.*
