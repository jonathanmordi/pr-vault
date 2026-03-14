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
    """Converts '1:52.34' or '52.34' to float seconds. Returns None if unparseable."""
    raw = raw.strip()
    try:
        if ':' in raw:
            parts = raw.split(':')
            return round(int(parts[0]) * 60 + float(parts[1]), 4)
        return round(float(raw), 4)
    except:
        return None

def upsert_pr_if_faster(athlete_id, team_id, event, new_seconds, display, meet_name, meet_date):
    """Writes to meet_appearances always. Updates track_prs only if faster."""

    # Always log the appearance
    supabase.table("meet_appearances").insert({
        "athlete_id": athlete_id,
        "team_id": team_id,
        "event": event,
        "time_seconds": new_seconds,
        "display_value": display,
        "meet_name": meet_name,
        "meet_date": meet_date,
        "was_pr": False
    }).execute()

    # Check for existing PR 
    try:
        result = supabase.table("track_prs") \
            .select("id, best_time_seconds") \
            .eq("athlete_id", athlete_id) \
            .eq("event", event) \
            .maybe_single() \
            .execute()
        existing = result.data if result else None
    except Exception:
        existing = None


    if existing is None:
        # First time running this event — insert
        supabase.table("track_prs").insert({
            "athlete_id": athlete_id,
            "team_id": team_id,
            "event": event,
            "best_time_seconds": new_seconds,
            "best_display": display,
            "set_on": meet_date,
            "set_at_meet": meet_name,
            "data_source": "tfrrs",
            "improvement_delta_pct": 0
        }).execute()
        print(f"  NEW PR inserted: {event} {display}")

    elif new_seconds < existing["best_time_seconds"]:
        # Faster time — update PR
        delta = ((existing["best_time_seconds"] - new_seconds)
                 / existing["best_time_seconds"]) * 100

        supabase.table("track_prs").update({
            "previous_best_seconds": existing["best_time_seconds"],
            "best_time_seconds": new_seconds,
            "best_display": display,
            "set_on": meet_date,
            "set_at_meet": meet_name,
            "improvement_delta_pct": round(delta, 4),
            "updated_at": "now()"
        }).eq("id", existing["id"]).execute()

        # Mark the appearance as a PR
        supabase.table("meet_appearances").update({
            "was_pr": True
        }).eq("athlete_id", athlete_id) \
          .eq("event", event) \
          .eq("meet_date", meet_date) \
          .execute()

        print(f"  PR UPDATED: {event} {display} (improved {round(delta, 2)}%)")

    else:
        print(f"  No PR: {event} {display} — not faster than existing")

def scrape_athlete(page, tfrrs_athlete_id, athlete_id, team_id):
    url = f"https://www.tfrrs.org/athletes/{tfrrs_athlete_id}"
    print(f"\nScraping {url}")

    page.goto(url, wait_until="domcontentloaded")
    page.wait_for_timeout(3000)

    rows = page.query_selector_all("table#all_bests tbody tr")
    print(f"  Found {len(rows)} result rows")

    for row in rows:
        tds = row.query_selector_all("td")

        # each row has pairs: event, time, event, time
        pairs = []
        i = 0
        while i + 1 < len(tds):
            event = tds[i].inner_text().strip()
            raw_time = tds[i + 1].inner_text().strip()
            if event and raw_time:
                pairs.append((event, raw_time))
            i += 2

        for event, raw_time in pairs:
            # clean wind reading like "11.10 (-0.2)" → "11.10"
            display = raw_time.split()[0].strip()

            new_seconds = parse_time_to_seconds(display)
            if new_seconds is None:
                continue

            print(f"  Found: {event} — {display}")
            upsert_pr_if_faster(
                athlete_id=athlete_id,
                team_id=team_id,
                event=event,
                new_seconds=new_seconds,
                display=display,
                meet_name="TFRRS import",
                meet_date=None
            )

def run_scraper():
    """Main entry point — loads athletes from Supabase and scrapes each one."""

    # Get all athletes on the team that have a TFRRS ID
    result = supabase.table("profiles") \
        .select("id, full_name, tfrrs_athlete_id, team_id") \
        .not_.is_("tfrrs_athlete_id", "null") \
        .execute()

    athletes = result.data
    print(f"Found {len(athletes)} athletes to scrape")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        # Set a realistic user agent so TFRRS doesn't block us
        page.set_extra_http_headers({
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        })

        for athlete in athletes:
            scrape_athlete(
                page=page,
                tfrrs_athlete_id=athlete["tfrrs_athlete_id"],
                athlete_id=athlete["id"],
                team_id=athlete["team_id"]
            )
            page.wait_for_timeout(3000)  # 3 second delay between athletes

        browser.close()
    print("\nScrape complete.")

if __name__ == "__main__":
    run_scraper()

"""
Don't run it yet — before we test it we need at least one athlete in your `profiles` table with a real `tfrrs_athlete_id`. 

Go to [tfrrs.org](https://tfrrs.org) and search for any D3 athlete — even yourself if you're on there. Click their profile and look at the URL. It'll look like:
```
https://www.tfrrs.org/athletes/6082790
"""