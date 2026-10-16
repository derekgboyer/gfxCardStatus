#!/usr/bin/env python3
"""Write or redact the Sparkle EdDSA private key without printing it.

write PATH reads the secret on stdin and stores one trimmed line at PATH
with mode 0600. redact reads tool output on stdin and replaces that secret
with [redacted]. SPARKLE_PRIVATE_KEY in the environment is the secret for
redact. The value is never written to stdout or stderr.
"""

import os
import stat
import sys
from pathlib import Path

REFUSAL = (
    "SPARKLE_PRIVATE_KEY must be the single-line base64 EdDSA private key "
    "from generate_keys. The value was not printed."
)


def one_line(raw):
    lines = [line.strip() for line in raw.strip().splitlines() if line.strip()]
    if len(lines) != 1:
        raise ValueError(REFUSAL)
    return lines[0]


def write_key(raw, path):
    secret = one_line(raw)
    destination = Path(path)
    destination.write_text(secret + "\n", encoding="utf-8")
    os.chmod(destination, stat.S_IRUSR | stat.S_IWUSR)


def redact(text, secret):
    redacted = text
    for line in secret.splitlines():
        token = line.strip()
        if len(token) >= 16:
            redacted = redacted.replace(token, "[redacted]")
    return redacted


def self_test():
    secret = "PRIV" + ("A" * 40) + "="
    try:
        one_line(secret + "\nsecond\n")
    except ValueError as exc:
        message = str(exc)
        if secret in message or "not printed" not in message:
            raise SystemExit("write refusal printed or was unclear")
    else:
        raise SystemExit("multiline private key was accepted")
    import tempfile

    directory = tempfile.mkdtemp()
    path = Path(directory) / "key"
    write_key(secret + "\n", path)
    if path.read_text(encoding="utf-8") != secret + "\n":
        raise SystemExit("private key file contents were unexpected")
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode != 0o600:
        raise SystemExit(f"private key file mode is {oct(mode)}")
    leaked = f"ERROR! Failed to decode base64 encoded key data from: {secret}\n"
    cleaned = redact(leaked, secret + "\n")
    if secret in cleaned or "[redacted]" not in cleaned:
        raise SystemExit("redaction left the private key in place")
    path.unlink()
    print("sparkle_private_key self-test ok")


def main(argv):
    if "--self-test" in argv[1:]:
        self_test()
        return 0
    if len(argv) >= 2 and argv[1] == "write":
        if len(argv) != 3:
            print("usage: sparkle_private_key.py write PATH", file=sys.stderr)
            return 1
        try:
            write_key(sys.stdin.read(), argv[2])
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        return 0
    if len(argv) >= 2 and argv[1] == "redact":
        secret = os.environ.get("SPARKLE_PRIVATE_KEY", "")
        sys.stdout.write(redact(sys.stdin.read(), secret))
        return 0
    print("usage: sparkle_private_key.py write PATH | redact | --self-test", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
