"""Pytest config: provide dummy Supabase creds before scraper.py is imported.

scraper.py calls create_client() at module import time. These env vars let the
test suite import it without a real .env / network — the pure parsing functions
under test never touch the client.
"""
import os

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "test-anon-key")
