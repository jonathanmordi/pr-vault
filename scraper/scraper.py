import os
import re
from dotenv import load_dotenv
from supabase import create_client
from playwright.sync_api import sync_playwright

load_dotenv()

supabase = create_client(
    os.getenv("SUPABASE_URL"),
    os.getenv("SUPABASE_KEY")
)

def parse_time_to_seconds(raw: str) -> float | None:
    """Converts '1:52.34' or '52.34' to float seconds. Returns None if not a time."""
    raw = raw.strip().split()[0]  # strip wind readings
    try:
        if ':' in raw:
            parts = raw.split(':')
            return round(int(parts[0]) * 60 + float(parts[1]), 4)
        val = float(raw)
        # field event marks are usually over 3m and under 100 — times are under 3 or over 60
        # this is a rough heuristic to avoid misclassifying marks as times
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
            is_better = new_meters > existing_mark  # further = better for field
            if existing_mark > 0:
                delta = ((new_meters - existing_mark) / existing_mark) * 100
            else:
                delta = 0
        else:
            existing_time = existing.get("best_time_seconds") or 9999
            is_better = new_seconds < existing_time  # faster = better for track
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
    url = f"https://www.tfrrs.org/athletes/{tfrrs_athlete_id}"
    print(f"\nScraping {url}")

    page.goto(url, wait_until="domcontentloaded")
    page.wait_for_timeout(3000)

    rows = page.query_selector_all("table#all_bests tbody tr")
    print(f"  Found {len(rows)} result rows")

    for row in rows:
        tds = row.query_selector_all("td")

        pairs = []
        i = 0
        while i + 1 < len(tds):
            event = tds[i].inner_text().strip()
            raw = tds[i + 1].inner_text().strip()
            if event and raw:
                pairs.append((event, raw))
            i += 2

        for event, raw in pairs:
            display = raw.split('\n')[0].strip()  # take only first line
            display = display.split()[0].strip()  # then strip wind reading

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

            print(f"  Found: {event} — {display}")
            upsert_pr_if_faster(
                athlete_id=athlete_id,
                team_id=team_id,
                event=event,
                new_seconds=new_seconds,
                new_meters=new_meters,
                display=display,
                meet_name="TFRRS import",
                meet_date=None
            )


def scrape_team_roster(page, team_url, team_id):
    """Scrapes all athlete IDs from a TFRRS team page."""
    print(f"\nFetching roster from {team_url}")

    page.goto(team_url, wait_until="domcontentloaded")
    page.wait_for_timeout(3000)

    # find all athlete profile links
    links = page.query_selector_all("a[href*='/athletes/']")
    
    seen = set()
    athletes = []
    for link in links:
        href = link.get_attribute("href")
        name = link.inner_text().strip()
        if not href or not name:
            continue
        # extract ID from URL like /athletes/8681460/Stevens/...
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
    # scrape both men's and women's teams so the roster stays complete
    team_urls = [
        "https://www.tfrrs.org/teams/tf/NJ_college_m_Stevens.html",
        "https://www.tfrrs.org/teams/tf/NJ_college_f_Stevens.html",
    ]

    # get team_id from Supabase
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
            # fetch roster once per team/gender to avoid duplicate scrapes
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
