#!/usr/bin/env python3
"""Collect deterministic ground truth for the Eval stand-in.

Combines STO severity counts, Gitleaks findings, Semgrep architecture rule hits
and changed-line coverage into one JSON document that eval_gate.py imports as
pre-confirmed findings.
"""

import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def source_span(path: str, start: int, end: int) -> str:
    # Semgrep OSS redacts extra.lines without a login, so read the source.
    try:
        lines = Path(path).read_text().splitlines()[start - 1:end]
    except OSError:
        return ""
    return " ".join(" ".join(lines).split())


def semgrep_hits(path: Path) -> list[dict]:
    if not path.exists():
        return []
    hits = []
    for r in json.loads(path.read_text()).get("results", []):
        extra = r.get("extra", {})
        meta = extra.get("metadata", {})
        if "criterion" not in meta:
            continue
        line = r["start"]["line"]
        text = source_span(r["path"], line, r["end"]["line"]) or extra.get("message", "")
        hits.append({
            "criterion": meta["criterion"],
            "severity": "high",
            "evidence": f"{r['path']}:{line} {text[:160]}",
        })
    return hits


def coverage_ratio(path: Path) -> float | None:
    if not path.exists():
        return None
    root = ET.parse(path).getroot()
    rate = root.get("line-rate")
    return round(float(rate), 4) if rate is not None else None


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--sto-critical", type=int, default=0)
    p.add_argument("--sto-high", type=int, default=0)
    p.add_argument("--secrets", type=int, default=0)
    p.add_argument("--semgrep-json", default="semgrep-arch.json")
    p.add_argument("--coverage-xml", default="coverage.xml")
    p.add_argument("--out", default="ground-truth.json")
    a = p.parse_args(argv)
    doc = {
        "sto_critical": a.sto_critical,
        "sto_high": a.sto_high,
        "secrets": a.secrets,
        "semgrep": semgrep_hits(Path(a.semgrep_json)),
        "coverage_changed_lines": coverage_ratio(Path(a.coverage_xml)),
    }
    Path(a.out).write_text(json.dumps(doc, indent=2))
    print(json.dumps({k: v for k, v in doc.items() if k != "semgrep"} | {"semgrep_hits": len(doc["semgrep"])}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
