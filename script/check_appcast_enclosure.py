#!/usr/bin/env python3
"""Require the appcast to advertise exactly one app zip.

EXPECT_ED_SIGNATURE=1 also requires a Sparkle edSignature on that enclosure.
"""

import os
import sys
import xml.etree.ElementTree as ET

SPARKLE_SIGNATURE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"


def check(path, zip_name, expect_signature):
    root = ET.parse(path).getroot()
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise SystemExit(f"appcast has {len(items)} items, expected 1")
    enclosure = items[0].find("enclosure")
    url = enclosure.get("url") if enclosure is not None else ""
    if not url.endswith("/" + zip_name) or "source" in url:
        raise SystemExit(f"appcast enclosure is not the app zip: {url}")
    signature = ""
    if enclosure is not None:
        signature = enclosure.get(SPARKLE_SIGNATURE) or enclosure.get("edSignature") or ""
    if expect_signature and not signature:
        raise SystemExit("appcast enclosure has no edSignature")
    print(f"appcast enclosure={url} edSignature={'yes' if signature else 'no'}")


def self_test():
    import tempfile
    from pathlib import Path

    good = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="https://github.com/example/gfxCardStatus/releases/download/v2.5/gfxCardStatus-2.5.zip" sparkle:edSignature="abc=" length="10" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
    directory = tempfile.mkdtemp()
    path = Path(directory) / "appcast.xml"
    path.write_text(good, encoding="utf-8")
    check(path, "gfxCardStatus-2.5.zip", True)
    unsigned = good.replace(' sparkle:edSignature="abc="', "")
    path.write_text(unsigned, encoding="utf-8")
    try:
        check(path, "gfxCardStatus-2.5.zip", True)
    except SystemExit as exc:
        if "edSignature" not in str(exc):
            raise
    else:
        raise SystemExit("unsigned appcast was accepted")
    check(path, "gfxCardStatus-2.5.zip", False)
    print("check_appcast_enclosure self-test ok")


def main(argv):
    if "--self-test" in argv[1:]:
        self_test()
        return 0
    if len(argv) != 3:
        print("usage: check_appcast_enclosure.py APPCAST.XML ZIP_NAME", file=sys.stderr)
        return 1
    expect = os.environ.get("EXPECT_ED_SIGNATURE") == "1"
    check(argv[1], argv[2], expect)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
