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
    clean_mark,
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
