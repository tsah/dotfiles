#!/usr/bin/env python3

"""Sanitize pasted OAuth URL/text.

This removes terminal-wrapping artifacts (spaces/newlines/zero-width chars) and
normalizes OAuth query parameters such as redirect_uri, scope, and state.

Examples:
  sanitize-oauth-url.py
  echo "https://..." | sanitize-oauth-url.py
  sanitize-oauth-url.py "https://..."
"""

from __future__ import annotations

import argparse
import re
import sys
from urllib.parse import parse_qsl, quote_plus, urlencode, urlsplit, urlunsplit

ZERO_WIDTH_RE = re.compile(r"[\u200B\u200C\u200D\uFEFF]")
WHITESPACE_RE = re.compile(r"\s+")

# Values that must never contain whitespace for OAuth URLs.
NO_SPACE_KEYS = {
    "redirect_uri",
    "state",
    "code_challenge",
    "code_challenge_method",
    "client_id",
    "response_type",
    "code",
}


def strip_invisible(text: str) -> str:
    return ZERO_WIDTH_RE.sub("", text)


def remove_all_whitespace(text: str) -> str:
    return WHITESPACE_RE.sub("", text)


def normalize_query(query: str) -> str:
    pairs = parse_qsl(query, keep_blank_values=True)
    if not pairs:
        return query

    normalized: list[tuple[str, str]] = []
    for key, value in pairs:
        key = remove_all_whitespace(strip_invisible(key))
        value = strip_invisible(value)

        if key == "scope":
            # Preserve intended token separation, but collapse accidental extras.
            value = " ".join(value.split())
        elif key in NO_SPACE_KEYS:
            value = remove_all_whitespace(value)
        else:
            value = value.strip()

        normalized.append((key, value))

    return urlencode(normalized, doseq=True, quote_via=quote_plus)


def sanitize(text: str) -> str:
    cleaned = strip_invisible(text).strip()
    cleaned = cleaned.strip('"').strip("'")
    cleaned = remove_all_whitespace(cleaned)

    parts = urlsplit(cleaned)
    if parts.scheme and parts.netloc and parts.query:
        normalized_query = normalize_query(parts.query)
        return urlunsplit((parts.scheme, parts.netloc, parts.path, normalized_query, parts.fragment))

    if "=" in cleaned:
        # Support sanitizing raw query strings too.
        has_prefix = cleaned.startswith("?")
        query = cleaned[1:] if has_prefix else cleaned
        normalized_query = normalize_query(query)
        return f"?{normalized_query}" if has_prefix else normalized_query

    return cleaned


def read_input(args: argparse.Namespace) -> str:
    if args.text:
        return " ".join(args.text)

    if not sys.stdin.isatty():
        return sys.stdin.read()

    print("Paste the string, then press Ctrl-D:", file=sys.stderr)
    return sys.stdin.read()


def main() -> int:
    parser = argparse.ArgumentParser(description="Sanitize pasted OAuth URL/text")
    parser.add_argument("text", nargs="*", help="Optional text to sanitize")
    args = parser.parse_args()

    raw = read_input(args)
    cleaned = sanitize(raw)

    print(cleaned)
    return 0 if cleaned else 1


if __name__ == "__main__":
    raise SystemExit(main())
