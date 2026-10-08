"""Unit tests for the pure parsing/classification helpers in scraper.py.

These are the functions that turn messy TFRRS HTML text into the numbers that
drive PRs, leaderboards, and school records. Everything the app ranks on flows
through here, so the edge cases (date ranges, wind readings, DNS/DNF, field vs
track) matter. No network or database is touched.
"""
import pytest

from scraper import (
    parse_meet_date,
    parse_time_to_seconds,
    parse_mark_to_meters,
    is_field_event,
    clean_event_name,
    parse_event_heading,
    guess_season,
    compute_prs,
    clean_mark,
    parse_list_event,
    parse_tfrrs_athlete_id,
    parse_place,
    parse_list_mark,
    parse_list_year,
    pick_list_url,
    pick_conference,
    list_label,
    build_rank_entries,
    parse_roster_rows,
    roster_changes,
    roster_read_looks_complete,
    name_changes,
)


class TestParseMeetDate:
    @pytest.mark.parametrize("raw,expected", [
        # Single dates, abbreviated and full month names
        ("Apr 18, 2025", "2025-04-18"),
        ("December 12, 2025", "2025-12-12"),
        # Same-month ranges -> last day
        ("Feb 27-28, 2026", "2026-02-28"),
        ("May 1-3, 2025", "2025-05-03"),
        # Extra whitespace around the dash and inside the string
        ("Mar  6- 7, 2026", "2026-03-07"),
        ("May  1- 3, 2025", "2025-05-03"),
        # Cross-month range -> end date
        ("February 28-March 1, 2025", "2025-03-01"),
    ])
    def test_all_documented_formats(self, raw, expected):
        assert parse_meet_date(raw) == expected

    def test_leading_and_trailing_whitespace(self):
        assert parse_meet_date("  Apr 18, 2025  ") == "2025-04-18"

    @pytest.mark.parametrize("bad", ["", None, "not a date", "13/40/2025", "Foo 99, 2025"])
    def test_unparseable_returns_none(self, bad):
        assert parse_meet_date(bad) is None


class TestParseTimeToSeconds:
    @pytest.mark.parametrize("raw,expected", [
        ("52.34", 52.34),          # flat sprint time
        ("1:52.34", 112.34),       # mm:ss
        ("4:05.00", 245.0),        # distance
        ("10:00.5", 600.5),
        ("9.58", 9.58),
    ])
    def test_valid_times(self, raw, expected):
        assert parse_time_to_seconds(raw) == pytest.approx(expected)

    def test_strips_wind_reading(self):
        # "10.12 (+1.2)" style — only the first whitespace token is kept
        assert parse_time_to_seconds("10.12 (+1.2)") == pytest.approx(10.12)

    @pytest.mark.parametrize("bad", ["", "DNS", "FOUL", "abc", "-"])
    def test_non_times_return_none(self, bad):
        assert parse_time_to_seconds(bad) is None


class TestParseMarkToMeters:
    @pytest.mark.parametrize("raw,expected", [
        ("6.45m", 6.45),
        ("6.45", 6.45),
        ("18.00m", 18.0),
        ("2.13", 2.13),
    ])
    def test_valid_marks(self, raw, expected):
        assert parse_mark_to_meters(raw) == pytest.approx(expected)

    def test_strips_trailing_token(self):
        assert parse_mark_to_meters("6.45m (something)") == pytest.approx(6.45)

    @pytest.mark.parametrize("bad", ["", "FOUL", "NH", "abc"])
    def test_unparseable_returns_none(self, bad):
        assert parse_mark_to_meters(bad) is None


class TestIsFieldEvent:
    @pytest.mark.parametrize("event", [
        "High Jump", "Long Jump", "Triple Jump", "Pole Vault",
        "Shot Put", "Discus", "Hammer", "Javelin", "Weight Throw",
        "Decathlon", "Heptathlon", "Pentathlon",
        "HJ", "LJ", "TJ", "PV", "SP", "DT", "HT", "JT",
    ])
    def test_field_events(self, event):
        assert is_field_event(event) is True

    @pytest.mark.parametrize("event", [
        "100 Meters", "200 Meters", "400 Meters", "800 Meters",
        "1500 Meters", "5000 Meters", "110 Hurdles", "400 Hurdles",
        "4x100 Relay",
    ])
    def test_running_events(self, event):
        assert is_field_event(event) is False

    def test_is_case_insensitive(self):
        assert is_field_event("shot put") is True
        assert is_field_event("SHOT PUT") is True


class TestCleanEventName:
    @pytest.mark.parametrize("raw,expected", [
        ("100 Meters (Indoor)", "100 Meters"),
        ("Long Jump (Outdoor)", "Long Jump"),
        ("800 Meters (Indoors)", "800 Meters"),
        ("Mile (Outdoors)", "Mile"),
        ("400 Meters Top↑", "400 Meters"),
        ("  200 Meters  ", "200 Meters"),
        ("High   Jump", "High Jump"),  # collapses internal whitespace
    ])
    def test_cleaning(self, raw, expected):
        assert clean_event_name(raw) == expected

    def test_case_insensitive_tag_removal(self):
        assert clean_event_name("100 Meters (INDOOR)") == "100 Meters"


class TestParseEventHeading:
    @pytest.mark.parametrize("raw, expected", [
        ("Long Jump (Indoor)    Top↑", ("Long Jump", "indoor")),
        ("200 Meters (Outdoor)", ("200 Meters", "outdoor")),
        ("High Jump (Outdoors)", ("High Jump", "outdoor")),
        ("Mile (INDOORS)", ("Mile", "indoor")),
        ("8k", ("8k", "xc")),
        ("5K", ("5K", "xc")),
        ("Mile", ("Mile", None)),
    ])
    def test_keeps_the_season(self, raw, expected):
        assert parse_event_heading(raw) == expected


class TestGuessSeason:
    @pytest.mark.parametrize("event, meet, date, expected", [
        ("8k", "Fall Classic", "2025-10-04", "xc"),
        ("Long Jump", "AARTFC Indoor Championships", "2026-03-07", "indoor"),
        ("Long Jump", "MAC Outdoor Championships", "2026-05-02", "outdoor"),
        ("60 Meters", "Invite", "2026-04-01", "indoor"),
        ("Hammer", "Invite", "2026-02-01", "outdoor"),
        ("Long Jump", "Invite", "2026-03-15", "indoor"),
        ("Long Jump", "Invite", "2026-03-16", "outdoor"),
        ("Long Jump", "Invite", "2025-12-06", "indoor"),
        ("Long Jump", None, None, "outdoor"),
    ])
    def test_rules(self, event, meet, date, expected):
        assert guess_season(event, meet, date) == expected


def result(event, season, date, seconds=None, meters=None, meet="Meet"):
    display = f"{meters:.2f}m" if meters is not None else f"{seconds:.2f}"
    return {"event": event, "season": season, "new_seconds": seconds, "new_meters": meters,
            "display": display, "meet_name": meet, "meet_date": date}


class TestComputePrs:
    def test_one_pr_per_event_per_season(self):
        prs = compute_prs([
            result("Long Jump", "indoor", "2026-02-01", meters=6.73),
            result("Long Jump", "outdoor", "2026-05-14", meters=6.91),
            result("Long Jump", "outdoor", "2026-04-11", meters=6.87),
        ])
        assert set(prs) == {("Long Jump", "indoor"), ("Long Jump", "outdoor")}
        assert prs[("Long Jump", "indoor")]["best_display"] == "6.73m"
        assert prs[("Long Jump", "outdoor")]["best_display"] == "6.91m"

    def test_improvement_over_the_best_before_that_day(self):
        prs = compute_prs([
            result("400 Meters", "outdoor", "2026-04-01", seconds=52.0),
            result("400 Meters", "outdoor", "2026-04-08", seconds=51.0),
            result("400 Meters", "outdoor", "2026-04-15", seconds=50.0),
        ])
        pr = prs[("400 Meters", "outdoor")]
        assert pr["best_time_seconds"] == 50.0
        assert pr["previous_best_seconds"] == 51.0
        assert pr["improvement_delta_pct"] == pytest.approx(1.9608, abs=1e-4)

    def test_field_improvement_and_no_previous_seconds(self):
        prs = compute_prs([
            result("Shot Put", "indoor", "2026-01-10", meters=14.0),
            result("Shot Put", "indoor", "2026-02-10", meters=14.7),
        ])
        pr = prs[("Shot Put", "indoor")]
        assert pr["improvement_delta_pct"] == pytest.approx(5.0)
        assert pr["previous_best_seconds"] is None

    def test_a_final_is_not_an_improvement_on_the_same_days_prelim(self):
        prs = compute_prs([
            result("55 Meters", "indoor", "2025-02-21", seconds=6.73),
            result("55 Meters", "indoor", "2025-02-21", seconds=6.60),
        ])
        assert prs[("55 Meters", "indoor")]["improvement_delta_pct"] == 0

    def test_ties_go_to_the_first_time_it_was_run(self):
        prs = compute_prs([
            result("800 Meters", "outdoor", "2026-05-01", seconds=118.0, meet="Later"),
            result("800 Meters", "outdoor", "2026-04-01", seconds=118.0, meet="First"),
        ])
        assert prs[("800 Meters", "outdoor")]["set_at_meet"] == "First"

    def test_seasons_never_mix(self):
        prs = compute_prs([
            result("200 Meters", "indoor", "2026-02-01", seconds=23.0),
            result("200 Meters", "outdoor", "2026-04-01", seconds=22.5),
        ])
        # The outdoor 22.5 is a debut outdoors, not an improvement on indoors.
        assert prs[("200 Meters", "outdoor")]["improvement_delta_pct"] == 0


class TestCleanMark:
    @pytest.mark.parametrize("raw,expected", [
        ("10.12", "10.12"),
        ("10.12 (+1.2)", "10.12"),          # drop wind reading
        ("1:52.34\nsome footnote", "1:52.34"),  # only first line
        ("6.45m", "6.45m"),
    ])
    def test_extracts_mark(self, raw, expected):
        assert clean_mark(raw) == expected

    @pytest.mark.parametrize("nonresult", [
        "DNS", "DNF", "FS", "FOUL", "NH", "DQ", "SCR", "",
    ])
    def test_non_results_return_none(self, nonresult):
        assert clean_mark(nonresult) is None

    def test_case_insensitive_nonresult(self):
        assert clean_mark("dns") is None


# ─── Performance-list ranks ───────────────────────────────────────────────────

class TestParseListEvent:
    @pytest.mark.parametrize("raw,expected", [
        ("100 Meters (Men)", "100 Meters"),
        (" Long Jump (Women) ", "Long Jump"),
        ("10,000 Meters", "10,000 Meters"),
        ("\n 400 Meters \n", "400 Meters"),
    ])
    def test_matches_athlete_page_names(self, raw, expected):
        assert parse_list_event(raw) == expected


class TestParseTfrrsAthleteId:
    def test_extracts_id(self):
        href = "https://tf.tfrrs.org/athletes/8668013/Misericordia/Jacob__Hunter"
        assert parse_tfrrs_athlete_id(href) == "8668013"

    @pytest.mark.parametrize("bad", [None, "", "https://tf.tfrrs.org/teams/tf/x.html"])
    def test_no_athlete_link(self, bad):
        assert parse_tfrrs_athlete_id(bad) is None


class TestParseListMark:
    @pytest.mark.parametrize("raw,expected", [
        (" 3:15.31 % ", "3:15.31"),  # footnote marker
        ("6.45m", "6.45m"),
        ("6212", "6212"),            # multi-event points
    ])
    def test_marks(self, raw, expected):
        assert parse_list_mark(raw) == expected

    @pytest.mark.parametrize("empty", [None, "", "   "])
    def test_empty(self, empty):
        assert parse_list_mark(empty) is None


class TestParsePlace:
    @pytest.mark.parametrize("raw,expected", [(" 12 ", 12), ("1", 1), ("6\n", 6)])
    def test_places(self, raw, expected):
        assert parse_place(raw) == expected

    @pytest.mark.parametrize("bad", ["", None, "-", "DQ"])
    def test_missing_place(self, bad):
        assert parse_place(bad) is None


class TestParseListYear:
    @pytest.mark.parametrize("name,season,expected", [
        # Conference lists put the year at the end
        ("Middle Atlantic Conference Indoor Performance List (2026)", "indoor", 2026),
        # NCAA indoor lists span two years: the season is the spring one
        ("2025-2026 NCAA Division III Indoor List", "indoor", 2026),
        ("2025_2026_NCAA_Division_III_Indoor_List_FINAL", "indoor", 2026),
        ("2026 NCAA Division III Outdoor Qualifying", "outdoor", 2026),
    ])
    def test_reads_year_from_name(self, name, season, expected):
        assert parse_list_year([name], [], season) == expected

    def test_next_indoor_season_never_reuses_last_years_label(self):
        # Early in the 2026-27 indoor season: a yearless name and only
        # December meets. Must be 2027, or it would overwrite indoor 2026.
        assert parse_list_year(["Indoor List"], ["Dec 5, 2026", "Dec 12, 2026"], "indoor") == 2027
        assert parse_list_year([None], ["Feb 27-28, 2027", "Dec 5, 2026"], "indoor") == 2027

    def test_outdoor_falls_back_to_latest_meet_year(self):
        assert parse_list_year([""], ["Mar 21, 2026", "May 2, 2026"], "outdoor") == 2026

    def test_tries_each_name(self):
        assert parse_list_year(["", "2026 NCAA Division III Outdoor Qualifying (FINAL)"], [], "outdoor") == 2026

    def test_unknown(self):
        assert parse_list_year([None], ["", "  "], "outdoor") is None


class TestPickListUrl:
    LINKS = [
        ("NCAA Div. II", "https://tf.tfrrs.org/lists/5603/2026_NCAA_Division_II_Outdoor"),
        ("NCAA Div. III", "https://tf.tfrrs.org/lists/5604/2026_NCAA_Division_III_Outdoor"),
        ("m", "https://tf.tfrrs.org/lists/5604/2026_NCAA_Division_III_Outdoor?gender=m"),
        ("Middle Atlantic Conferences", "https://tf.tfrrs.org/lists/5732/MAC_Outdoor_List?gender=f"),
    ]

    def test_exact_label_match(self):
        # "NCAA Div. II" must not match "NCAA Div. III"
        assert pick_list_url(self.LINKS, "NCAA Div. III").endswith("/5604/2026_NCAA_Division_III_Outdoor")

    def test_strips_query(self):
        assert pick_list_url(self.LINKS, "Middle Atlantic Conferences") == \
            "https://tf.tfrrs.org/lists/5732/MAC_Outdoor_List"

    def test_missing(self):
        assert pick_list_url(self.LINKS, "Liberty League") is None


class TestPickConference:
    def test_skips_region(self):
        assert pick_conference(["DIII Metro Region", "Middle Atlantic Conferences"]) == \
            "Middle Atlantic Conferences"

    def test_none(self):
        assert pick_conference([" ", "DIII Metro Region"]) is None


class TestListLabel:
    @pytest.mark.parametrize("name,label", [
        ("Middle Atlantic Conferences", "MAC"),
        ("New Jersey Athletic Conference", "NJAC"),
        ("SUNYAC", "SUNYAC"),
        ("Empire 8", "E8"),
        ("University Athletic Association of the East", "UAAE"),
    ])
    def test_labels(self, name, label):
        assert list_label(name) == label


class TestBuildRankEntries:
    ROSTER = {"111": "athlete-a", "222": "athlete-b"}
    INFO = {
        "scope": "conference", "label": "MAC", "season": "outdoor",
        "season_year": 2026, "list_name": "MAC Outdoor List", "list_url": "u",
    }

    @staticmethod
    def row(place, tfrrs_id, mark="10.50"):
        return {"place": f" {place} ", "href": f"https://tf.tfrrs.org/athletes/{tfrrs_id}/Stevens/X",
                "mark": f" {mark} ", "date": "Apr 30, 2026"}

    def test_keeps_only_roster_athletes(self):
        blocks = [{"event": "100 Meters (Men)", "rows": [
            self.row(1, "999"), self.row(2, "111"), self.row(3, "998"), self.row(4, "222"),
        ]}]
        entries = build_rank_entries(blocks, self.ROSTER, "team", self.INFO)
        assert [(e["athlete_id"], e["rank"], e["list_size"]) for e in entries] == [
            ("athlete-a", 2, 4), ("athlete-b", 4, 4),
        ]
        a = entries[0]
        assert a["event"] == "100 Meters"
        assert a["mark_display"] == "10.50"
        assert a["team_id"] == "team" and a["label"] == "MAC" and a["season_year"] == 2026

    def test_skips_relays_and_rows_without_athletes(self):
        blocks = [
            {"event": "4 x 100 Relay (Men)", "rows": [self.row(1, "111")]},
            {"event": "200 Meters (Men)", "rows": [{"place": "1", "href": None, "mark": "", "date": ""}]},
        ]
        assert build_rank_entries(blocks, self.ROSTER, "team", self.INFO) == []

    def test_conference_lists_have_no_cut(self):
        blocks = [{"event": "100 Meters (Men)", "rows": [self.row(1, "111")]}]
        (entry,) = build_rank_entries(blocks, self.ROSTER, "team", self.INFO)
        assert entry["cut_rank"] is None and entry["cut_mark"] is None

    def test_national_lists_record_the_mark_at_the_cut(self):
        rows = [self.row(i, "111" if i == 21 else str(900 + i), f"10.{i:02d}") for i in range(1, 26)]
        info = {**self.INFO, "scope": "national", "label": "D3", "cut_rank": 22}
        (entry,) = build_rank_entries([{"event": "100 Meters (Men)", "rows": rows}],
                                      self.ROSTER, "team", info)
        assert entry["rank"] == 21
        assert entry["cut_rank"] == 22 and entry["cut_mark"] == "10.22"

    def test_cut_is_per_event(self):
        sprint = [self.row(i, "111" if i == 1 else str(900 + i), f"10.{i:02d}") for i in range(1, 4)]
        jump = [self.row(i, "222" if i == 2 else str(800 + i), f"7.{10 - i}0m") for i in range(1, 4)]
        info = {**self.INFO, "scope": "national", "label": "D3", "cut_rank": 2}
        entries = build_rank_entries(
            [{"event": "100 Meters (Men)", "rows": sprint}, {"event": "Long Jump (Men)", "rows": jump}],
            self.ROSTER, "team", info)
        assert {e["event"]: e["cut_mark"] for e in entries} == {"100 Meters": "10.02", "Long Jump": "7.80m"}

    def test_list_shorter_than_the_cut_has_no_cut_mark(self):
        info = {**self.INFO, "scope": "national", "label": "D3", "cut_rank": 20}
        blocks = [{"event": "100 Meters (Men)", "rows": [self.row(1, "111"), self.row(2, "999")]}]
        (entry,) = build_rank_entries(blocks, self.ROSTER, "team", info)
        assert entry["cut_rank"] == 20 and entry["cut_mark"] is None

    def test_keeps_best_place_if_listed_twice(self):
        blocks = [{"event": "Long Jump", "rows": [self.row(7, "111", "6.40m"), self.row(3, "111", "6.80m")]}]
        (entry,) = build_rank_entries(blocks, self.ROSTER, "team", self.INFO)
        assert entry["rank"] == 3 and entry["mark_display"] == "6.80m"


class TestParseRosterRows:
    @staticmethod
    def row(name, tfrrs_id, year="SR-4"):
        return {"name": f" {name} ", "href": f"https://www.tfrrs.org/athletes/{tfrrs_id}/Stevens/X",
                "year": f" {year} "}

    def test_reads_name_id_and_class_year(self):
        assert parse_roster_rows([self.row("Adamo,   James", "111", "SO-2")]) == [
            {"name": "Adamo, James", "tfrrs_id": "111", "year": "SO-2"},
        ]

    def test_skips_rows_without_an_athlete_and_duplicates(self):
        rows = [self.row("A, B", "111"), {"name": "", "href": None, "year": ""}, self.row("A, B", "111")]
        assert [a["tfrrs_id"] for a in parse_roster_rows(rows)] == ["111"]

    def test_missing_year_is_none(self):
        assert parse_roster_rows([{"name": "A, B", "href": "/athletes/5/X", "year": ""}])[0]["year"] is None


class TestRosterChanges:
    PROFILES = [
        {"id": "a", "tfrrs_athlete_id": "1", "on_roster": True},
        {"id": "b", "tfrrs_athlete_id": "2", "on_roster": True},
        {"id": "c", "tfrrs_athlete_id": "3", "on_roster": False},
        {"id": "d", "tfrrs_athlete_id": "4", "on_roster": False},
    ]

    def test_on_roster_grouped_by_year_and_dropped_off_listed(self):
        current, left = roster_changes(self.PROFILES, {"1": "SR-4", "3": "JR-3"})
        assert current == {"SR-4": ["a"], "JR-3": ["c"]}  # c came back
        assert left == ["b"]  # d had already left

    def test_nobody_left_when_everyone_is_listed(self):
        _, left = roster_changes(self.PROFILES[:2], {"1": "FR-1", "2": "FR-1"})
        assert left == []

    def test_a_partial_read_is_not_trusted(self):
        assert roster_read_looks_complete(on_roster_now=88, seen=87)
        assert roster_read_looks_complete(on_roster_now=88, seen=60)
        assert not roster_read_looks_complete(on_roster_now=88, seen=12)
        assert roster_read_looks_complete(on_roster_now=0, seen=3)


class TestNameChanges:
    def test_names_follow_the_roster(self):
        profiles = [
            {"id": "a", "tfrrs_athlete_id": "1", "full_name": "jonathan mordi test"},
            {"id": "b", "tfrrs_athlete_id": "2", "full_name": "Chen, Lily"},
            {"id": "c", "tfrrs_athlete_id": "3", "full_name": "Gone, Person"},
            {"id": "d", "tfrrs_athlete_id": "4", "full_name": "Doug Winant"},
        ]
        names = {"1": "Mordi, Jonathan", "2": "Chen, Lily", "4": "Winant, Douglas"}
        assert name_changes(profiles, names) == [("a", "Mordi, Jonathan"), ("d", "Winant, Douglas")]

    def test_order_and_capitalization_dont_count(self):
        profiles = [
            {"id": "a", "tfrrs_athlete_id": "1", "full_name": "Tyler Hackett"},
            {"id": "b", "tfrrs_athlete_id": "2", "full_name": "Affoumani, Daniel"},
        ]
        names = {"1": "Hackett, Tyler", "2": "Affoumani, DanieL"}
        assert name_changes(profiles, names) == []
