#!/usr/bin/env python3
"""Check the Release app's Sparkle feed URL and public key.

PLIST is the built Info.plist. FEED_URL is the GitHub appcast URL passed to
xcodebuild. SPARKLE_PUBLIC_ED_KEY, when set, is the sanitized bare public key.
"""

import os
import plistlib
import sys

PROJECT_DEFAULT_KEY = "4duXTeQPGZRwAyOAG2Wvqjkuk23es7QEuuy9FcjPEao="


def check(info, feed_url, override):
    feed = info.get("SUFeedURL", "")
    key = info.get("SUPublicEDKey", "")
    want_key = override or PROJECT_DEFAULT_KEY
    source = "repository variable" if override else "project default"
    ok = True
    if feed != feed_url or not isinstance(feed, str) or "$(" in feed:
        print(f"SUFeedURL={feed!r}, expected {feed_url!r}", file=sys.stderr)
        ok = False
    if key != want_key or not isinstance(key, str) or "$(" in key:
        print("SUPublicEDKey was not the expected key.", file=sys.stderr)
        print(f"SUPublicEDKey in Info.plist={key!r}", file=sys.stderr)
        print(f"expected {want_key!r} ({source})", file=sys.stderr)
        ok = False
    print(f"SUFeedURL={feed}")
    print(f"SUPublicEDKey source={source}")
    return ok


def self_test():
    feed = "https://github.com/example/gfxCardStatus/releases/latest/download/appcast.xml"
    info = {
        "SUFeedURL": feed,
        "SUPublicEDKey": PROJECT_DEFAULT_KEY,
    }
    if not check(info, feed, ""):
        raise SystemExit("project default key was rejected")
    other = "kwGfxsca37dMWVwYY/YElw+U+vF6QDXHnXbqCpWNm18="
    info["SUPublicEDKey"] = other
    if not check(info, feed, other):
        raise SystemExit("repository key was rejected")
    info["SUPublicEDKey"] = "override"
    if check(info, feed, other):
        raise SystemExit("literal override was accepted as the public key")
    print("verify_release_info_plist self-test ok")


def main(argv):
    if "--self-test" in argv[1:]:
        self_test()
        return 0
    plist_path = os.environ["PLIST"]
    feed_url = os.environ["FEED_URL"]
    override = os.environ.get("SPARKLE_PUBLIC_ED_KEY", "").strip()
    with open(plist_path, "rb") as handle:
        info = plistlib.load(handle)
    return 0 if check(info, feed_url, override) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
