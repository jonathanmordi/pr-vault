import os
import re
import sys
import uuid
from datetime import date, datetime
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


# The roster table (NAME, YEAR). Other tables on the team page, like top
# marks, link athletes too, so read this one specifically.
_ROSTER_JS = """() => {
  const table = [...document.querySelectorAll('table')].find(t => {
    const h = [...t.querySelectorAll('thead th')].map(th => th.textContent.trim().toUpperCase());
    return h.length === 2 && h[0] === 'NAME' && h[1] === 'YEAR';
  });
  if (!table) return null;
  return [...table.querySelectorAll('tbody tr')].map(tr => {
    const a = tr.querySelector("a[href*='/athletes/']");
    const cells = tr.querySelectorAll('td');
    return {name: a ? a.textContent : '', href: a ? a.getAttribute('href') : null,
            year: cells[1] ? cells[1].textContent : ''};
  });
}"""


def parse_roster_rows(rows):
    """Roster table rows → [{'name', 'tfrrs_id', 'year'}], once per athlete.
    'year' is the class year as TFRRS shows it ('SR-4'), or None."""
    athletes, seen = [], set()
    for row in rows:
        tfrrs_id = parse_tfrrs_athlete_id(row.get('href'))
        name = re.sub(r'\s+', ' ', row.get('name') or '').strip()
        if not tfrrs_id or not name or tfrrs_id in seen:
            continue
        seen.add(tfrrs_id)
        athletes.append({'name': name, 'tfrrs_id': tfrrs_id,
                         'year': (row.get('year') or '').strip() or None})
    return athletes


def scrape_team_roster(page, team_url, team_id):
    """Athletes on a TFRRS team's current roster, with class years.

    Returns (athletes, from_roster_table). If the roster table can't be
    found, falls back to every athlete link on the page: good enough for
    scraping results, but not for deciding who has left the team."""
    print(f"\nFetching roster from {team_url}")
    page.goto(team_url, wait_until="domcontentloaded")
    page.wait_for_timeout(3000)

    rows = page.evaluate(_ROSTER_JS)
    if rows is not None:
        athletes = parse_roster_rows(rows)
        print(f"  Found {len(athletes)} athletes on roster")
        return athletes, True

    print("  WARNING: no roster table; using every athlete link on the page")
    links = page.query_selector_all("a[href*='/athletes/']")
    athletes = parse_roster_rows([
        {'name': link.inner_text(), 'href': link.get_attribute("href")} for link in links
    ])
    print(f"  Found {len(athletes)} athletes linked")
    return athletes, False


# ─── Roster status ────────────────────────────────────────────────────────────

# If a roster read finds fewer than this share of the athletes currently on
# the roster, assume the page didn't load right rather than that half the
# team left at once.
MIN_ROSTER_SHARE = 0.5


def roster_changes(profiles, roster):
    """What to change after reading the current roster.

    profiles: [{'id', 'tfrrs_athlete_id', 'on_roster'}] on the team
    roster:   {tfrrs_id: class_year} from the team pages
    Returns (current, left): current maps class year → ids of profiles on
    the roster now; left lists ids that were on it and no longer are.
    """
    current, left = {}, []
    for p in profiles:
        tfrrs_id = p.get('tfrrs_athlete_id')
        if tfrrs_id in roster:
            current.setdefault(roster[tfrrs_id], []).append(p['id'])
        elif tfrrs_id and p.get('on_roster'):
            left.append(p['id'])
    return current, left


def name_key(name):
    """'Hackett, Tyler' and 'tyler  hackett' → 'tyler hackett'."""
    name = re.sub(r'\s+', ' ', name or '').strip()
    if ',' in name:
        last, first = name.split(',', 1)
        name = f"{first.strip()} {last.strip()}"
    return name.lower()


def name_changes(profiles, names):
    """Profiles whose name really differs from the TFRRS roster, as
    [(id, tfrrs_name)]: a name typed at sign-up, or a changed first name.
    'Last, First' vs 'First Last' and capitalization don't count, so TFRRS
    typos like 'DanieL' don't overwrite a cleaner name."""
    return [(p['id'], names[p['tfrrs_athlete_id']]) for p in profiles
            if p.get('tfrrs_athlete_id') in names
            and name_key(p.get('full_name')) != name_key(names[p['tfrrs_athlete_id']])]


def roster_read_looks_complete(on_roster_now, seen):
    return on_roster_now == 0 or seen >= on_roster_now * MIN_ROSTER_SHARE


def update_roster_status(team_id, roster, names=None, dry_run=False):
    """Marks who's on the team's current TFRRS roster, with class years, and
    who has left it (alumni). Showing up on the roster again undoes leaving.
    names ({tfrrs_id: name}) keeps profile names matching TFRRS."""
    profiles = supabase.table("profiles") \
        .select("id, full_name, tfrrs_athlete_id, on_roster") \
        .eq("team_id", team_id) \
        .not_.is_("tfrrs_athlete_id", "null") \
        .execute().data or []
    on_now = sum(1 for p in profiles if p['on_roster'])
    current, left = roster_changes(profiles, roster)
    if left and not roster_read_looks_complete(on_now, len(roster)):
        print(f"  WARNING: the roster read found {len(roster)} athletes but {on_now} are "
              f"on the roster; not marking anyone as gone")
        left = []

    renames = name_changes(profiles, names or {})
    by_id = {p['id']: p['full_name'] for p in profiles}
    print(f"\nRoster: {sum(len(ids) for ids in current.values())} on the roster, "
          f"{len(left)} newly gone, {len(renames)} renamed")
    for profile_id in left:
        print(f"  left the roster: {by_id[profile_id]}")
    for profile_id, name in renames:
        print(f"  renamed: {by_id[profile_id]} -> {name}")
    if dry_run:
        return

    for profile_id, name in renames:
        supabase.table("profiles").update({"full_name": name}).eq("id", profile_id).execute()

    for year, ids in current.items():
        supabase.table("profiles") \
            .update({"on_roster": True, "left_roster_on": None, "class_year": year}) \
            .in_("id", ids).execute()
    if left:
        supabase.table("profiles") \
            .update({"on_roster": False, "left_roster_on": date.today().isoformat()}) \
            .in_("id", left).execute()


# ─── Performance-list ranks ───────────────────────────────────────────────────

LIST_INDEXES = {
    "indoor": "https://tf.tfrrs.org/indoor_lists.html",
    "outdoor": "https://tf.tfrrs.org/outdoor_lists.html",
}
# (link text on the list index pages, label shown in the app)
NATIONAL_LIST = ("NCAA Div. III", "D3")
LIST_DEPTH = "500"  # deepest option TFRRS offers; the default is ~25-50
# How many athletes the NCAA D3 championships take in each individual event
# (2026: the top 20 declared indoors, top 22 outdoors). The real cut can run
# a little deeper when qualifiers don't declare, so the app calls it a
# projection.
NATIONALS_FIELD = {"indoor": 20, "outdoor": 22}

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


def parse_list_year(names: list[str | None], meet_dates: list[str], season: str) -> int | None:
    """The season a list belongs to. Indoor seasons are named for the spring
    they end in, so the 2025-26 indoor list is 2026.

    Tries each name in turn ('MAC Indoor List (2026)', '2025-2026 NCAA Division
    III Indoor List', '2026 NCAA Division III Outdoor Qualifying'), then falls
    back to the latest meet date, where an Aug-Dec indoor meet counts toward
    the next year. Getting this wrong would overwrite last season's ranks.
    """
    for name in names:
        name = (name or '').strip()
        m = re.search(r'\((\d{4})\)\s*$', name)
        if m:
            return int(m.group(1))
        m = re.search(r'(?<!\d)(\d{4})\s*[-_–]\s*(\d{4})(?!\d)', name)
        if m:
            return int(m.group(2))
        m = re.search(r'(?<!\d)(20\d{2})(?!\d)', name)
        if m:
            return int(m.group(1))

    years = []
    for raw in meet_dates:
        d = parse_meet_date(raw) if raw.strip() else None
        if d:
            year, month = int(d[:4]), int(d[5:7])
            years.append(year + 1 if season == 'indoor' and month >= 8 else year)
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
    list_info: scope, label, season, season_year, list_name, list_url, and
               cut_rank for lists with a qualifying cut (national)
    """
    cut_rank = list_info.get('cut_rank')
    best = {}
    for block in blocks:
        event = parse_list_event(block.get('event', ''))
        rows = block.get('rows', [])
        if not event or 'relay' in event.lower():
            continue
        # The mark of the last athlete inside the cut. A list that isn't that
        # deep yet has no cut: everyone on it is in.
        cut_mark = (parse_list_mark(rows[cut_rank - 1].get('mark'))
                    if cut_rank and len(rows) >= cut_rank else None)
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
                'cut_rank': cut_rank,
                'cut_mark': cut_mark,
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


def scrape_list(page, url, season):
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
    return name, parse_list_year([selected, name], dates, season), blocks


def load_roster(team_id):
    """{tfrrs_athlete_id: profile_id} for everyone on the team linked to TFRRS."""
    result = supabase.table("profiles") \
        .select("id, tfrrs_athlete_id") \
        .eq("team_id", team_id) \
        .not_.is_("tfrrs_athlete_id", "null") \
        .execute()
    return {r["tfrrs_athlete_id"]: r["id"] for r in result.data or []}


def save_ranks(entries):
    try:
        supabase.table("list_ranks").upsert(
            entries, on_conflict="athlete_id,event,scope,season,season_year"
        ).execute()
    except Exception as e:
        if 'cut_' not in str(e):
            raise
        # The list_rank_cuts migration hasn't been applied yet.
        print("  NOTE: list_ranks has no cut columns yet; saving ranks without cuts")
        supabase.table("list_ranks").upsert(
            [{k: v for k, v in entry.items() if not k.startswith('cut_')} for entry in entries],
            on_conflict="athlete_id,event,scope,season,season_year",
        ).execute()


def scrape_list_ranks(page, team_id, conference, dry_run=False):
    """Records each athlete's rank on the national and conference lists."""
    roster = load_roster(team_id)
    print(f"\nRanking {len(roster)} athletes on TFRRS lists "
          f"(conference: {conference or 'unknown'})")

    for info in find_rank_lists(page, conference):
        try:
            name, year, blocks = scrape_list(page, info["url"], info["season"])
            if year is None:
                print(f"  WARNING: couldn't tell which season {info['url']} is; skipping")
                continue
            entries = build_rank_entries(blocks, roster, team_id, {
                **info, "season_year": year, "list_name": name, "list_url": info["url"],
                "cut_rank": NATIONALS_FIELD[info["season"]] if info["scope"] == "national" else None,
            })
            depth = max((len(b['rows']) for b in blocks), default=0)
            print(f"  {name} ({info['season']} {year}): {len(entries)} ranks, "
                  f"up to {depth} deep")

            if dry_run:
                for e in sorted(entries, key=lambda e: e['rank'])[:5]:
                    cut = f"  (cut #{e['cut_rank']}: {e['cut_mark']})" if e['cut_rank'] else ""
                    print(f"    #{e['rank']} of {e['list_size']} {e['label']}  "
                          f"{e['event']}  {e['mark_display']}{cut}")
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
                save_ranks(entries)
        except Exception as e:
            print(f"  WARNING: skipped {info['url']}: {e}")
        page.wait_for_timeout(3000)


def run_scraper(ranks_only=False, roster_only=False, dry_run=False):
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
        roster_ids = {}  # tfrrs_id → class year, across the team pages
        roster_names = {}  # tfrrs_id → name as TFRRS shows it
        roster_complete = True
        for team_url in team_urls:
            gender = 'F' if '_f_' in team_url else 'M'
            if ranks_only:
                page.goto(team_url, wait_until="domcontentloaded")
                page.wait_for_timeout(3000)
                conference = read_conference(page)
                break

            roster, from_table = scrape_team_roster(page, team_url, team_id)
            roster_complete = roster_complete and from_table and bool(roster)
            roster_ids.update({a["tfrrs_id"]: a["year"] for a in roster})
            roster_names.update({a["tfrrs_id"]: a["name"] for a in roster})
            conference = conference or read_conference(page)
            if roster_only:
                continue

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

        # Roster status is extra too, and only trustworthy when every team
        # page's roster table was read.
        if not ranks_only:
            if roster_complete:
                try:
                    update_roster_status(team_id, roster_ids, roster_names, dry_run=dry_run)
                except Exception as e:
                    print(f"\nWARNING: roster status skipped: {e}")
            else:
                print("\nWARNING: couldn't read every roster table; roster status unchanged")
        if roster_only:
            browser.close()
            print("\nScrape complete.")
            return

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
    # --roster-only       just read the rosters and update who's on the team
    # --dry-run           print instead of saving (ranks, or the roster with
    #                     --roster-only)
    dry_run = "--dry-run" in sys.argv
    roster_only = "--roster-only" in sys.argv
    run_scraper(ranks_only=not roster_only and (dry_run or "--ranks-only" in sys.argv),
                roster_only=roster_only, dry_run=dry_run)