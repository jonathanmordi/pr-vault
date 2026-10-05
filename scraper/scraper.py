import os
import re
import sys
import uuid
from datetime import datetime
from dotenv import load_dotenv
from supabase import create_client
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout

load_dotenv()

supabase = create_client(
    os.getenv("SUPABASE_URL"),
    os.getenv("SUPABASE_KEY")
)


def parse_meet_date(raw: str) -> str | None:
    """Parse TFRRS date strings into 'YYYY-MM-DD'.
    Handles all observed formats:
      'Apr 18, 2025'              → '2025-04-18'
      'Feb 27-28, 2026'           → '2026-02-28'   (last day)
      'Mar  6- 7, 2026'           → '2026-03-07'   (extra spaces)
      'February 28-March  1, 2025'→ '2025-03-01'   (cross-month range)
      'May  1- 3, 2025'           → '2025-05-03'   (extra spaces + range)
      'December 12, 2025'         → '2025-12-12'   (full month name)
    """
    if not raw:
        return None
    raw = raw.strip()
    # Normalize multiple spaces to single space
    raw = re.sub(r'\s+', ' ', raw)
    # Normalize dashes with spaces around them: "6- 7" or "6 -7" → "6-7"
    raw = re.sub(r'\s*-\s*', '-', raw)

    # Cross-month range: "February 28-March 1, 2025" → use the end date
    m = re.match(r'^(\w+)\s+\d+-(\w+)\s+(\d+),\s*(\d{4})$', raw)
    if m:
        end_month, end_day, year = m.group(2), m.group(3), m.group(4)
        try:
            for fmt in ("%b %d, %Y", "%B %d, %Y"):
                try:
                    return datetime.strptime(f"{end_month} {end_day}, {year}", fmt).strftime("%Y-%m-%d")
                except ValueError:
                    continue
        except Exception:
            pass

    # Same-month range: "Feb 27-28, 2026" or "May 1-3, 2025" → use last day
    m = re.match(r'^(\w+)\s+\d+-(\d+),\s*(\d{4})$', raw)
    if m:
        month, end_day, year = m.group(1), m.group(2), m.group(3)
        for fmt in ("%b %d, %Y", "%B %d, %Y"):
            try:
                return datetime.strptime(f"{month} {end_day}, {year}", fmt).strftime("%Y-%m-%d")
            except ValueError:
                continue

    # Single date: "Apr 18, 2025" or "December 12, 2025"
    for fmt in ("%b %d, %Y", "%B %d, %Y"):
        try:
            return datetime.strptime(raw, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue

    print(f"  WARNING: Could not parse date: [{raw}]")
    return None


def parse_time_to_seconds(raw: str) -> float | None:
    """Converts '1:52.34' or '52.34' to float seconds. Returns None if not a time."""
    parts = raw.strip().split()  # strip wind readings
    if not parts:
        return None
    raw = parts[0]
    try:
        if ':' in raw:
            parts = raw.split(':')
            return round(int(parts[0]) * 60 + float(parts[1]), 4)
        val = float(raw)
        return round(val, 4)
    except:
        return None


def parse_mark_to_meters(raw: str) -> float | None:
    """Converts '6.45m' or '6.45' to float meters. Returns None if unparseable."""
    parts = raw.strip().split()
    if not parts:
        return None
    raw = parts[0]
    try:
        return round(float(raw.replace('m', '')), 4)
    except:
        return None


def is_field_event(event: str) -> bool:
    field_events = [
        'hj', 'lj', 'tj', 'pv',
        'sp', 'dt', 'ht', 'jt',
        'jump', 'throw', 'put', 'vault',
        'discus', 'hammer', 'javelin', 'shot', 'triple', 'high', 'long', 'pole',
        'decathlon', 'heptathlon', 'pentathlon',
    ]
    return any(k in event.lower() for k in field_events)


def clean_event_name(raw: str) -> str:
    """Clean event name from thead: strip '(Indoor)', '(Outdoor)', 'Top↑', whitespace."""
    raw = re.sub(r'\(Indoor\)|\(Outdoor\)|\(Indoors\)|\(Outdoors\)|Top↑', '', raw, flags=re.IGNORECASE)
    return re.sub(r'\s+', ' ', raw).strip()


def clean_mark(raw: str) -> str | None:
    """Extract just the mark/time from td[0], skipping DNS/DNF/FS and wind readings."""
    raw = raw.strip()
    first_line = raw.split('\n')[0].strip()

    # Skip non-results
    if any(x in first_line.upper() for x in ['DNS', 'DNF', 'FS', 'FOUL', 'NH', 'DQ', 'SCR']):
        return None

    # Take just the numeric part (strip wind reading in parens)
    mark = first_line.split('(')[0].strip()
    tokens = mark.split()
    if not tokens:
        return None
    return tokens[0].strip()


def check_and_update_school_record(team_id, gender, event, new_seconds, new_meters, display, holder_name, meet_date):
    """If the new mark beats the school record, update it."""
    try:
        # Determine season from meet date
        season = 'indoor'
        if meet_date and len(meet_date) >= 7:
            month = int(meet_date[5:7])
            season = 'outdoor' if 3 <= month <= 8 else 'indoor'

        result = supabase.table("school_records") \
            .select("id, record_mark_seconds, record_mark_meters") \
            .eq("team_id", team_id) \
            .eq("event", event) \
            .eq("gender", gender) \
            .eq("season", season) \
            .maybe_single() \
            .execute()
        existing = result.data if result else None
    except Exception:
        return

    if existing is None:
        return  # no school record on file for this event — skip

    is_field = new_meters is not None

    if is_field:
        existing_mark = existing.get("record_mark_meters") or 0
        is_new_record = new_meters > existing_mark
    else:
        existing_time = existing.get("record_mark_seconds") or 9999
        is_new_record = new_seconds < existing_time

    if is_new_record:
        year = int(meet_date[:4]) if meet_date and len(meet_date) >= 4 else None
        supabase.table("school_records").update({
            "record_mark_seconds": new_seconds,
            "record_mark_meters": new_meters,
            "record_display": display,
            "holder_name": holder_name,
            "year_set": year,
        }).eq("id", existing["id"]).execute()
        print(f"  🏆 SCHOOL RECORD BROKEN: {event} {display} (was {existing.get('record_mark_seconds') or existing.get('record_mark_meters')})")


def upsert_pr_if_faster(athlete_id, team_id, event, new_seconds, new_meters, display, meet_name, meet_date, gender, holder_name):
    """Writes to meet_appearances always. Updates track_prs only if better."""

    # Always log the appearance
    supabase.table("meet_appearances").upsert(
        {
            "athlete_id": athlete_id,
            "team_id": team_id,
            "event": event,
            "time_seconds": new_seconds,
            "mark_meters": new_meters,
            "display_value": display,
            "meet_name": meet_name,
            "meet_date": meet_date,
            "was_pr": False
        },
        on_conflict="athlete_id,event,meet_name,meet_date,display_value"
    ).execute()

    # Check for existing PR
    try:
        result = supabase.table("track_prs") \
            .select("id, best_time_seconds, best_mark_meters") \
            .eq("athlete_id", athlete_id) \
            .eq("event", event) \
            .maybe_single() \
            .execute()
        existing = result.data if result else None
    except Exception:
        existing = None

    is_field = new_meters is not None

    if existing is None:
        # Brand new PR
        supabase.table("track_prs").insert({
            "athlete_id": athlete_id,
            "team_id": team_id,
            "event": event,
            "best_time_seconds": new_seconds,
            "best_mark_meters": new_meters,
            "best_display": display,
            "set_on": meet_date,
            "set_at_meet": meet_name,
            "data_source": "tfrrs",
            "improvement_delta_pct": 0
        }).execute()
        print(f"  NEW PR inserted: {event} {display}")

        # Check if this also breaks the school record
        check_and_update_school_record(
            team_id, gender, event, new_seconds, new_meters,
            display, holder_name, meet_date
        )
    else:
        if is_field:
            existing_mark = existing.get("best_mark_meters") or 0
            is_better = new_meters > existing_mark
            if existing_mark > 0:
                delta = ((new_meters - existing_mark) / existing_mark) * 100
            else:
                delta = 0
        else:
            existing_time = existing.get("best_time_seconds") or 9999
            is_better = new_seconds < existing_time
            if existing_time < 9999:
                delta = ((existing_time - new_seconds) / existing_time) * 100
            else:
                delta = 0

        if is_better:
            supabase.table("track_prs").update({
                "previous_best_seconds": existing.get("best_time_seconds"),
                "best_time_seconds": new_seconds,
                "best_mark_meters": new_meters,
                "best_display": display,
                "set_on": meet_date,
                "set_at_meet": meet_name,
                "improvement_delta_pct": round(delta, 4),
                "updated_at": "now()"
            }).eq("id", existing["id"]).execute()
            print(f"  PR UPDATED: {event} {display} (improved {round(delta, 2)}%)")

            # Check if this also breaks the school record
            check_and_update_school_record(
                team_id, gender, event, new_seconds, new_meters,
                display, holder_name, meet_date
            )
        else:
            print(f"  No PR: {event} {display} — not better than existing")


def scrape_athlete(page, tfrrs_athlete_id, athlete_id, team_id, gender, athlete_name):
    """Scrapes all meet appearances from an athlete's TFRRS event history."""
    url = f"https://www.tfrrs.org/athletes/{tfrrs_athlete_id}"
    print(f"\nScraping {url}")

    page.goto(url, wait_until="domcontentloaded")
    page.wait_for_timeout(3000)

    section = page.query_selector("div#event-history")
    if not section:
        print("  WARNING: No event-history section found")
        return

    tables = section.query_selector_all("table.table-hover")
    print(f"  Found {len(tables)} event tables")

    # Collect all results first, then sort chronologically
    all_results = []
    for table in tables:
        thead = table.query_selector("thead")
        if not thead:
            continue

        event = clean_event_name(thead.inner_text())
        if not event:
            continue

        rows = table.query_selector_all("tbody tr")
        for row in rows:
            tds = row.query_selector_all("td")
            if len(tds) < 3:
                continue

            raw_mark = tds[0].inner_text().strip()
            meet_name = tds[1].inner_text().strip()
            raw_date = tds[2].inner_text().strip()

            display = clean_mark(raw_mark)
            if display is None:
                continue

            meet_date = parse_meet_date(raw_date)

            if is_field_event(event):
                new_meters = parse_mark_to_meters(display)
                new_seconds = None
                if new_meters is None:
                    continue
            else:
                new_seconds = parse_time_to_seconds(display)
                new_meters = None
                if new_seconds is None:
                    continue

            all_results.append({
                "event": event,
                "new_seconds": new_seconds,
                "new_meters": new_meters,
                "display": display,
                "meet_name": meet_name,
                "meet_date": meet_date,
            })

    # Sort by date (oldest first) so PRs build up chronologically
    all_results.sort(key=lambda r: r["meet_date"] or "0000-00-00")

    for r in all_results:
        print(f"  {r['event']}: {r['display']} @ {r['meet_name']} ({r['meet_date']})")
        upsert_pr_if_faster(
            athlete_id=athlete_id,
            team_id=team_id,
            event=r["event"],
            new_seconds=r["new_seconds"],
            new_meters=r["new_meters"],
            display=r["display"],
            meet_name=r["meet_name"],
            meet_date=r["meet_date"],
            gender=gender,
            holder_name=athlete_name,
        )

    print(f"  Total appearances logged: {len(all_results)}")


def scrape_team_roster(page, team_url, team_id):
    """Scrapes all athlete IDs from a TFRRS team page."""
    print(f"\nFetching roster from {team_url}")
    page.goto(team_url, wait_until="domcontentloaded")
    page.wait_for_timeout(3000)

    links = page.query_selector_all("a[href*='/athletes/']")
    seen = set()
    athletes = []

    for link in links:
        href = link.get_attribute("href")
        name = link.inner_text().strip()
        if not href or not name:
            continue

        parts = href.split('/')
        try:
            idx = parts.index('athletes')
            tfrrs_id = parts[idx + 1]
            if tfrrs_id.isdigit() and tfrrs_id not in seen:
                seen.add(tfrrs_id)
                athletes.append({"name": name, "tfrrs_id": tfrrs_id})
        except (ValueError, IndexError):
            continue

    print(f"  Found {len(athletes)} athletes on roster")
    return athletes


# ─── Performance-list ranks ───────────────────────────────────────────────────

LIST_INDEXES = {
    "indoor": "https://tf.tfrrs.org/indoor_lists.html",
    "outdoor": "https://tf.tfrrs.org/outdoor_lists.html",
}
# (link text on the list index pages, label shown in the app)
NATIONAL_LIST = ("NCAA Div. III", "D3")
LIST_DEPTH = "500"  # deepest option TFRRS offers; the default is ~25-50

# TFRRS hides every event block but the first, and innerText is empty for
# hidden elements, so read textContent.
_LIST_ROWS_JS = """() => [...document.querySelectorAll('div.row[class*="gender_"]')].map(block => ({
  event: block.querySelector('.custom-table-title h3')?.textContent || '',
  rows: [...block.querySelectorAll('.performance-list-row')].map(r => ({
    place: r.querySelector('.col-place')?.textContent || '',
    href: r.querySelector('.col-athlete a')?.getAttribute('href') || null,
    mark: r.querySelector('[data-label="Time"], [data-label="Mark"], [data-label="Points"]')?.textContent || '',
    date: r.querySelector('[data-label="Meet Date"]')?.textContent || '',
  })),
}))"""


def parse_list_event(raw: str) -> str:
    """'100 Meters (Men)' → '100 Meters', matching the athlete-page names."""
    raw = re.sub(r'\((?:Men|Women)\)', '', clean_event_name(raw or ''))
    return re.sub(r'\s+', ' ', raw).strip()


def parse_tfrrs_athlete_id(href: str | None) -> str | None:
    """'https://tf.tfrrs.org/athletes/8668013/Misericordia/Jacob__Hunter' → '8668013'."""
    m = re.search(r'/athletes/(\d+)', href or '')
    return m.group(1) if m else None


def parse_list_mark(raw: str | None) -> str | None:
    """' 3:15.31 % ' → '3:15.31'. Drops footnote markers after the mark."""
    tokens = (raw or '').split()
    return tokens[0] if tokens else None


def parse_place(raw: str) -> int | None:
    """' 12 ' → 12. Ties repeat the same number on consecutive rows."""
    m = re.match(r'\s*(\d+)', raw or '')
    return int(m.group(1)) if m else None


def parse_list_year(selected_list: str | None, meet_dates: list[str]) -> int | None:
    """Season year from the list picker ('... Outdoor List (2026)'), falling
    back to the latest meet date on the list."""
    m = re.search(r'\((\d{4})\)\s*$', (selected_list or '').strip())
    if m:
        return int(m.group(1))
    years = [int(d[:4]) for d in (parse_meet_date(x) for x in meet_dates if x.strip()) if d]
    return max(years) if years else None


def pick_list_url(links: list[tuple[str, str]], link_text: str) -> str | None:
    """URL of the list whose link on the index page reads exactly `link_text`."""
    for text, href in links:
        if text.strip() == link_text and '/lists/' in href:
            return href.split('?')[0]
    return None


def pick_conference(league_links: list[str]) -> str | None:
    """A team page links its conference and its NCAA region; return the conference."""
    for text in league_links:
        text = text.strip()
        if text and 'region' not in text.lower():
            return text
    return None


def list_label(conference: str) -> str:
    """Short display name: 'Middle Atlantic Conferences' → 'MAC', 'SUNYAC' → 'SUNYAC'."""
    parts = []
    for word in re.findall(r'[A-Za-z0-9]+', conference):
        if word.islower():
            continue  # "of", "the"
        parts.append(word if word.isupper() and len(word) > 1 else word[0].upper())
    return ''.join(parts) or conference


def build_rank_entries(blocks, roster, team_id, list_info):
    """Turns scraped list blocks into list_ranks rows for athletes on our roster.

    blocks:    [{'event': str, 'rows': [{'place', 'href', 'mark', 'date'}]}]
    roster:    {tfrrs_athlete_id: profile_id}
    list_info: scope, label, season, season_year, list_name, list_url
    """
    best = {}
    for block in blocks:
        event = parse_list_event(block.get('event', ''))
        rows = block.get('rows', [])
        if not event or 'relay' in event.lower():
            continue
        for row in rows:
            athlete_id = roster.get(parse_tfrrs_athlete_id(row.get('href')))
            place = parse_place(row.get('place', ''))
            if not athlete_id or place is None:
                continue
            key = (athlete_id, event)
            if key in best and best[key]['rank'] <= place:
                continue
            best[key] = {
                'team_id': team_id,
                'athlete_id': athlete_id,
                'event': event,
                'scope': list_info['scope'],
                'label': list_info['label'],
                'season': list_info['season'],
                'season_year': list_info['season_year'],
                'rank': place,
                'list_size': len(rows),
                'mark_display': parse_list_mark(row.get('mark')),
                'list_name': list_info['list_name'],
                'list_url': list_info['list_url'],
            }
    return list(best.values())


def read_conference(page):
    """Reads the conference name off a TFRRS team page that's already open."""
    texts = page.eval_on_selector_all(
        "a[href*='/leagues/']", "as => as.map(a => a.textContent.trim())")
    return pick_conference(texts)


def find_rank_lists(page, conference):
    """Finds this season's national and conference lists, indoor and outdoor.
    List ids change every season, so look them up by name each run."""
    targets = [("national", *NATIONAL_LIST)]
    if conference:
        targets.append(("conference", conference, list_label(conference)))
    found = []
    for season, index_url in LIST_INDEXES.items():
        page.goto(index_url, wait_until="domcontentloaded")
        page.wait_for_timeout(3000)
        links = page.eval_on_selector_all(
            "a[href*='/lists/']", "as => as.map(a => [a.textContent.trim(), a.href])")
        for scope, link_text, label in targets:
            url = pick_list_url(links, link_text)
            if url:
                found.append({"scope": scope, "label": label, "season": season, "url": url})
            else:
                print(f"  WARNING: no {season} list called '{link_text}'")
    return found


def scrape_list(page, url):
    """Loads a TFRRS performance list at its deepest setting, both genders.
    Returns (list name, season year, event blocks)."""
    page.goto(url, wait_until="domcontentloaded")
    page.wait_for_timeout(3000)
    before = page.eval_on_selector_all('.performance-list-row', 'rs => rs.length')
    page.select_option("select[name=limit]", LIST_DEPTH)
    page.select_option("select[name=gender]", "")
    # The filter form reloads the list into a Turbo frame.
    page.eval_on_selector("form[action*='list_data']", "f => f.requestSubmit()")
    try:
        page.wait_for_function(
            f"() => document.querySelectorAll('.performance-list-row').length !== {before}",
            timeout=60000,
        )
    except PlaywrightTimeout:
        print(f"  WARNING: deeper list never loaded for {url}; using the default depth")
    page.wait_for_timeout(1000)

    blocks = page.evaluate(_LIST_ROWS_JS)
    selected = page.eval_on_selector(
        "select[name=other_lists]", "s => s.options[s.selectedIndex]?.text || ''")
    name = page.title().replace('TFRRS |', '').strip()
    dates = [r['date'] for b in blocks for r in b['rows']]
    return name, parse_list_year(selected, dates), blocks


def load_roster(team_id):
    """{tfrrs_athlete_id: profile_id} for everyone on the team linked to TFRRS."""
    result = supabase.table("profiles") \
        .select("id, tfrrs_athlete_id") \
        .eq("team_id", team_id) \
        .not_.is_("tfrrs_athlete_id", "null") \
        .execute()
    return {r["tfrrs_athlete_id"]: r["id"] for r in result.data or []}


def scrape_list_ranks(page, team_id, conference, dry_run=False):
    """Records each athlete's rank on the national and conference lists."""
    roster = load_roster(team_id)
    print(f"\nRanking {len(roster)} athletes on TFRRS lists "
          f"(conference: {conference or 'unknown'})")

    for info in find_rank_lists(page, conference):
        try:
            name, year, blocks = scrape_list(page, info["url"])
            if year is None:
                print(f"  WARNING: couldn't tell which season {info['url']} is; skipping")
                continue
            entries = build_rank_entries(blocks, roster, team_id, {
                **info, "season_year": year, "list_name": name, "list_url": info["url"],
            })
            depth = max((len(b['rows']) for b in blocks), default=0)
            print(f"  {name} ({info['season']} {year}): {len(entries)} ranks, "
                  f"up to {depth} deep")

            if dry_run:
                for e in sorted(entries, key=lambda e: e['rank'])[:5]:
                    print(f"    #{e['rank']} of {e['list_size']} {e['label']}  "
                          f"{e['event']}  {e['mark_display']}")
                continue

            # Rewrite the whole season so athletes who were pushed off the
            # list don't keep a stale rank.
            supabase.table("list_ranks").delete() \
                .eq("team_id", team_id) \
                .eq("scope", info["scope"]) \
                .eq("season", info["season"]) \
                .eq("season_year", year) \
                .execute()
            if entries:
                supabase.table("list_ranks").upsert(
                    entries, on_conflict="athlete_id,event,scope,season,season_year"
                ).execute()
        except Exception as e:
            print(f"  WARNING: skipped {info['url']}: {e}")
        page.wait_for_timeout(3000)


def run_scraper(ranks_only=False, dry_run=False):
    team_urls = [
        "https://www.tfrrs.org/teams/tf/NJ_college_m_Stevens.html",
        "https://www.tfrrs.org/teams/tf/NJ_college_f_Stevens.html",
    ]

    team_result = supabase.table("teams").select("id").execute()
    teams = team_result.data
    if not teams:
        print("No teams found in database")
        return
    team_id = teams[0]["id"]

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.set_extra_http_headers({
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        })

        conference = None
        for team_url in team_urls:
            gender = 'F' if '_f_' in team_url else 'M'
            if ranks_only:
                page.goto(team_url, wait_until="domcontentloaded")
                page.wait_for_timeout(3000)
                conference = read_conference(page)
                break

            roster = scrape_team_roster(page, team_url, team_id)
            conference = conference or read_conference(page)

            for athlete in roster:
                try:
                    existing = supabase.table("profiles") \
                        .select("id") \
                        .eq("tfrrs_athlete_id", athlete["tfrrs_id"]) \
                        .maybe_single() \
                        .execute()
                except Exception:
                    existing = None

                if existing and existing.data:
                    athlete_id = existing.data["id"]
                    print(f"\nExisting athlete: {athlete['name']}")
                else:
                    new_id = str(uuid.uuid4())
                    supabase.table("profiles").insert({
                        "id": new_id,
                        "team_id": team_id,
                        "role": "athlete",
                        "full_name": athlete["name"],
                        "tfrrs_athlete_id": athlete["tfrrs_id"],
                        "gender": gender,
                    }).execute()
                    athlete_id = new_id
                    print(f"\nNew athlete added: {athlete['name']} ({gender})")

                scrape_athlete(
                    page=page,
                    tfrrs_athlete_id=athlete["tfrrs_id"],
                    athlete_id=athlete_id,
                    team_id=team_id,
                    gender=gender,
                    athlete_name=athlete["name"],
                )

                page.wait_for_timeout(3000)

        # Ranks are extra: a TFRRS layout change or a database that doesn't
        # have list_ranks yet shouldn't fail the nightly PR scrape.
        try:
            scrape_list_ranks(page, team_id, conference, dry_run=dry_run)
        except Exception as e:
            print(f"\nWARNING: list ranks skipped: {e}")

        browser.close()

    print("\nScrape complete.")


if __name__ == "__main__":
    # --ranks-only        skip athlete pages, just refresh list ranks
    # --dry-run           print the ranks instead of saving (implies --ranks-only)
    dry_run = "--dry-run" in sys.argv
    run_scraper(ranks_only=dry_run or "--ranks-only" in sys.argv, dry_run=dry_run)