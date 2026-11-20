#!/usr/bin/env python3
"""Record one component's build in the release manifest (releases/<release>.yaml).

The manifest is the hand-off between ILMP Build and ILMP Deploy: one entry per
component with the digest, the commit it was built from, the build execution
and the Eval verdict bound to that digest. The format is deliberately flat so
the deploy side can read it with awk (see resolve-release.sh).

Prints RELEASE_COMPLETE=true|false (true once every component has an entry).
"""

import argparse
import datetime
import re
import sys
from pathlib import Path

COMPONENTS = ("calc-engine", "service-layer")
FIELDS = ("image", "tag", "digest", "commit", "build_url", "eval_verdict", "eval_score", "recorded_at")


def load(path: Path) -> dict:
    entries, current = {}, None
    if path.exists():
        for line in path.read_text().splitlines():
            m = re.match(r"^  ([a-z-]+):$", line)
            if m:
                current = entries.setdefault(m.group(1), {})
                continue
            m = re.match(r'^    ([a-z_]+): "(.*)"$', line)
            if m and current is not None:
                current[m.group(1)] = m.group(2)
    return entries


def dump(release: str, entries: dict) -> str:
    out = [f'release: "{release}"', "components:"]
    for name in sorted(entries):
        out.append(f"  {name}:")
        out.extend(f'    {k}: "{entries[name][k]}"' for k in FIELDS if k in entries[name])
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--file", required=True)
    p.add_argument("--release", required=True)
    p.add_argument("--component", required=True, choices=COMPONENTS)
    for f in ("image", "tag", "digest", "commit", "build-url", "eval-verdict", "eval-score"):
        p.add_argument(f"--{f}", required=True)
    a = p.parse_args(argv)
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", a.digest):
        print(f"refusing to record malformed digest {a.digest!r}", file=sys.stderr)
        return 1
    path = Path(a.file)
    entries = load(path)
    entries[a.component] = {
        "image": a.image, "tag": a.tag, "digest": a.digest, "commit": a.commit,
        "build_url": a.build_url, "eval_verdict": a.eval_verdict, "eval_score": a.eval_score,
        "recorded_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dump(a.release, entries))
    print("RELEASE_COMPLETE=" + ("true" if all(c in entries for c in COMPONENTS) else "false"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
