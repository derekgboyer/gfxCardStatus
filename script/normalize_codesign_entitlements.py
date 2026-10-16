#!/usr/bin/env python3
"""Normalize codesign -d --entitlements text for comparison.

Empty output and a bare [Dict] are the same: no entitlements. An Executable=
line from a combined stderr dump is ignored. Anything else is kept as-is.
"""

import sys


def normalize(text):
    lines = [
        line.strip()
        for line in text.splitlines()
        if line.strip() and not line.startswith("Executable=")
    ]
    if not lines or lines == ["[Dict]"]:
        return "empty\n"
    return "\n".join(lines) + "\n"


def self_test():
    assert normalize("") == "empty\n"
    assert normalize("[Dict]\n") == "empty\n"
    assert normalize("Executable=/tmp/Downloader\n[Dict]\n") == "empty\n"
    sandbox = "\n".join(
        [
            "[Dict]",
            "[Key] com.apple.security.app-sandbox",
            "[Value]",
            "[Bool] true",
        ]
    )
    assert "app-sandbox" in normalize(sandbox)
    assert normalize(sandbox) != "empty\n"
    print("normalize_codesign_entitlements self-test ok")


def main(argv):
    if "--self-test" in argv[1:]:
        self_test()
        return 0
    sys.stdout.write(normalize(sys.stdin.read()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
