#!/usr/bin/env python3
"""Extract a Sparkle Ed25519 public key from a bare value or a generate_keys snippet.

The repository variable SPARKLE_PUBLIC_ED_KEY is the bare base64 public key.
generate_keys also prints that key inside a SUPublicEDKey plist snippet, and
that whole snippet is accepted here. The private key is never printed.
"""

import base64
import re
import sys

PUBLIC_KEY_BYTES = 32

SNIPPET = re.compile(
    r"<\s*key\s*>\s*SUPublicEDKey\s*</\s*key\s*>\s*<\s*string\s*>(.*?)</\s*string\s*>",
    re.IGNORECASE | re.DOTALL,
)

MISSING = (
    "SPARKLE_PUBLIC_ED_KEY does not contain an Ed25519 public key. "
    "Set it to the bare base64 key (32 bytes; the text inside the <string> "
    "element generate_keys prints) or to the full "
    "<key>SUPublicEDKey</key><string>…</string> snippet. "
    "Do not put the private key in this variable. The value was not printed."
)

AMBIGUOUS = (
    "SPARKLE_PUBLIC_ED_KEY contains more than one Ed25519 public key. "
    "Set it to a single bare base64 key. The values were not printed."
)


def decode_public_key(text):
    candidate = text.strip().strip("'\"`")
    if not re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", candidate):
        return None
    padded = candidate + ("=" * ((-len(candidate)) % 4))
    try:
        raw = base64.b64decode(padded, validate=True)
    except Exception:
        return None
    if len(raw) != PUBLIC_KEY_BYTES:
        return None
    return base64.b64encode(raw).decode("ascii")


def _unique(keys):
    found = []
    for key in keys:
        if key and key not in found:
            found.append(key)
    if len(found) == 1:
        return found[0]
    if len(found) > 1:
        raise ValueError(AMBIGUOUS)
    return None


def extract_public_ed_key(raw):
    if raw is None or not str(raw).strip():
        raise ValueError(MISSING)
    text = (
        str(raw)
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", '"')
        .replace("&#39;", "'")
    )
    snippets = SNIPPET.findall(text)
    if snippets:
        key = _unique(decode_public_key(body) for body in snippets)
        if key is None:
            raise ValueError(MISSING)
        return key

    stripped = text.strip()
    keys = [decode_public_key(stripped)]
    collapsed = re.sub(r"\s+", "", stripped)
    if collapsed != stripped:
        keys.append(decode_public_key(collapsed))
    key = _unique(keys)
    if key:
        return key

    tokens = []
    for token in re.split(r"\s+", stripped):
        tokens.append(decode_public_key(token))
    key = _unique(tokens)
    if key is None:
        raise ValueError(MISSING)
    return key


def _expect(raw, want):
    got = extract_public_ed_key(raw)
    if got != want:
        raise SystemExit(f"self-test mismatch: got {got!r}")


def _expect_error(raw, needle):
    try:
        extract_public_ed_key(raw)
    except ValueError as exc:
        message = str(exc)
        if needle and needle in message:
            raise SystemExit("self-test error included the rejected input")
        if needle and needle in raw and needle in message:
            raise SystemExit("self-test error included the rejected input")
        if "not printed" not in message:
            raise SystemExit(f"self-test error was unclear: {message}")
        if needle and needle in message:
            raise SystemExit("self-test error included the rejected input")
        return
    raise SystemExit("self-test accepted a value that should fail")


def self_test():
    bare = "4duXTeQPGZRwAyOAG2Wvqjkuk23es7QEuuy9FcjPEao="
    other = "kwGfxsca37dMWVwYY/YElw+U+vF6QDXHnXbqCpWNm18="
    _expect(bare, bare)
    _expect(f"  {bare}\n", bare)
    _expect(f'"{bare}"', bare)
    _expect(bare.replace("=", ""), bare)
    _expect(
        "\n".join(
            [
                "<key>SUPublicEDKey</key>",
                f"<string>{other}</string>",
            ]
        ),
        other,
    )
    _expect(
        "\n".join(
            [
                "A key has been generated and saved in your keychain.",
                "    <key>SUPublicEDKey</key>",
                f"    <string>{other}</string>",
                "",
            ]
        ),
        other,
    )
    _expect(f"&lt;key&gt;SUPublicEDKey&lt;/key&gt;&lt;string&gt;{bare}&lt;/string&gt;", bare)
    wrapped = "\n".join([bare[:20], bare[20:]])
    _expect(wrapped, bare)
    _expect_error("", "")
    _expect_error("not-a-key", "not-a-key")
    _expect_error(
        "\n".join(
            [
                f"<key>SUPublicEDKey</key><string>{bare}</string>",
                f"<key>SUPublicEDKey</key><string>{other}</string>",
            ]
        ),
        bare,
    )
    private = base64.b64encode(b"\x11" * 96).decode("ascii")
    _expect_error(private, private)
    print("sparkle_public_ed_key self-test ok")


def main(argv):
    if "--self-test" in argv[1:]:
        self_test()
        return 0
    raw = sys.stdin.read()
    try:
        key = extract_public_ed_key(raw)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    sys.stdout.write(key + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
