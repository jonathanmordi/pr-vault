import os
import re
from datetime import datetime
from dotenv import load_dotenv
from supabase import create_client
from playwright.sync_api import sync_playwright

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
            # Try abbreviated month first, then full
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
    raw = raw.strip().split()[0]  # strip wind readings
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
    raw = raw.strip().split()[0]
    try:
        return round(float(raw.replace('m', '')), 4)
    except:
        return None

def is_field_event(event: str) -> bool:
    field_events = [
        'hj', 'lj', 'tj', 'pv',
        'sp', 'dt', 'ht', 'jt',
        'jump', 'throw', 'put', 'vault',
        'discus', 'hammer', 'javelin', 'shot', 'triple', 'high', 'long', 'pole'
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
    mark = mark.split()[0].strip()
    if not mark:
        return None
    return mark


def upsert_pr_if_faster(athlete_id, team_id, event, new_seconds, new_meters, display, meet_name, meet_date):
    """Writes to meet_appearances always. Updates track_prs only if better."""

    # Always log the appearance
    supabase.table("meet_appearances").insert({
        "athlete_id": athlete_id,
        "team_id": team_id,
        "event": event,
        "time_seconds": new_seconds,
        "mark_meters": new_meters,
        "display_value": display,
        "meet_name": meet_name,
        "meet_date": meet_date,
        "was_pr": False
    }).execute()

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
        else:
            print(f"  No PR: {event} {display} — not better than existing")


def scrape_athlete(page, tfrrs_athlete_id, athlete_id, team_id):
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


def run_scraper():
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

        for team_url in team_urls:
            gender = 'F' if '_f_' in team_url else 'M'
            roster = scrape_team_roster(page, team_url, team_id)

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
                    import uuid
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
                    team_id=team_id
                )
                page.wait_for_timeout(3000)

        browser.close()
    print("\nScrape complete.")


if __name__ == "__main__":
    run_scraper()