#!/usr/bin/env python3
"""Check the ad-hoc Release build's Info.plist and CFBundleVersion.

PLIST is the built Info.plist. CFBundleVersion must be 5000 plus
git rev-list --count HEAD.
"""

import os
import plistlib
import subprocess
import sys


def check(info, commit_count):
    ok = True
    expected = {
        "SUFeedURL": "https://gfx.io/appcasts/release.xml",
        "SUPublicEDKey": "4duXTeQPGZRwAyOAG2Wvqjkuk23es7QEuuy9FcjPEao=",
        "CFBundleIdentifier": "com.codykrieger.gfxCardStatus",
    }
    for key, want in expected.items():
        value = info.get(key, "")
        if value != want:
            print(f"{key}={value!r}, expected {want!r}", file=sys.stderr)
            ok = False
    for key in (
        "SUFeedURL",
        "SUPublicEDKey",
        "CFBundleVersion",
        "CFBundleShortVersionString",
        "LSMinimumSystemVersion",
    ):
        value = info.get(key, "")
        if not isinstance(value, str) or not value or "$(" in value:
            print(f"{key} is missing or was not expanded: {value!r}", file=sys.stderr)
            ok = False
    build = info.get("CFBundleVersion", "")
    expected_build = str(5000 + commit_count)
    if build != expected_build:
        print(
            f"CFBundleVersion={build!r}, expected {expected_build} (5000 + {commit_count} commits)",
            file=sys.stderr,
        )
        ok = False
    if info.get("LSUIElement") is not True:
        print("LSUIElement is not true", file=sys.stderr)
        ok = False
    print(f"SUFeedURL={info.get('SUFeedURL')}")
    print(f"CFBundleVersion={build}")
    return ok


def main(argv):
    plist_path = os.environ["PLIST"]
    with open(plist_path, "rb") as handle:
        info = plistlib.load(handle)
    count = int(subprocess.check_output(["git", "rev-list", "--count", "HEAD"], text=True).strip())
    return 0 if check(info, count) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
