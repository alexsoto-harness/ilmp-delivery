#!/usr/bin/env python3
"""SPDJI Eval stand-in: deterministic scoring for the ILMP release gate.

The LLM never decides the verdict. Agents propose findings, the verifier marks
them confirmed/refuted/inconclusive, and this script scores them with fixed
weights. Scanner findings arrive pre-confirmed and cannot be refuted.

Modes:
  live    score findings from the reviewer and verifier agents plus ground truth
  replay  load a recorded verdict (demo safety net), re-bound to this artifact
  api     POST {repo, commit, image_digest, release} to EVAL_API_URL (their Eval)

Writes the verdict JSON to --out and KEY=VALUE outputs to --env-out.
"""

import argparse
import json
import os
import sys
import urllib.request
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
SEVERITIES = ("critical", "high", "medium", "low")
VERIFICATIONS = ("confirmed", "refuted", "inconclusive", "pre-confirmed")
FINDING_KEYS = ("criterion", "severity", "evidence")


class EvalError(Exception):
    pass


def load_criteria(path: Path) -> dict:
    criteria = yaml.safe_load(path.read_text())
    weights = sum(d["weight"] for d in criteria["dimensions"])
    if abs(weights - 1.0) > 1e-6:
        raise EvalError(f"dimension weights sum to {weights}, expected 1.0")
    return criteria


def criterion_index(criteria: dict) -> dict:
    return {cid: d["id"] for d in criteria["dimensions"] for cid in d["criteria"]}


def validate_finding(f: dict, known: dict) -> None:
    missing = [k for k in FINDING_KEYS if k not in f]
    if missing:
        raise EvalError(f"finding missing {missing}: {f}")
    if f["criterion"] not in known:
        raise EvalError(f"unknown criterion {f['criterion']}")
    if f["severity"] not in SEVERITIES:
        raise EvalError(f"unknown severity {f['severity']}")
    if f.get("verification", "inconclusive") not in VERIFICATIONS:
        raise EvalError(f"unknown verification {f.get('verification')}")


def ground_truth_findings(gt: dict) -> list[dict]:
    """Scanner results become pre-confirmed findings the agents cannot dismiss."""
    out = []
    for sev in ("critical", "high"):
        n = int(gt.get(f"sto_{sev}", 0))
        if n:
            out.append({"criterion": "S1", "severity": sev, "source": "sto",
                        "evidence": f"{n} {sev} vulnerability finding(s) in STO",
                        "verification": "pre-confirmed"})
    if int(gt.get("secrets", 0)):
        out.append({"criterion": "S2", "severity": "critical", "source": "gitleaks",
                    "evidence": f"{gt['secrets']} secret(s) detected", "verification": "pre-confirmed"})
    for r in gt.get("semgrep", []):
        out.append({"criterion": r["criterion"], "severity": r.get("severity", "high"),
                    "source": "semgrep", "evidence": r["evidence"], "verification": "pre-confirmed"})
    cov = gt.get("coverage_changed_lines")
    if cov is not None and float(cov) < 0.8:
        out.append({"criterion": "U1", "severity": "medium", "source": "coverage",
                    "evidence": f"changed-line coverage {float(cov):.0%}", "verification": "pre-confirmed"})
    return out


def score(criteria: dict, findings: list[dict]) -> dict:
    known = criterion_index(criteria)
    penalty = criteria["severity_penalty"]
    for f in findings:
        validate_finding(f, known)

    counted = [f for f in findings if f.get("verification", "inconclusive") != "refuted"]
    dims = []
    for d in criteria["dimensions"]:
        mine = [f for f in counted if known[f["criterion"]] == d["id"]]
        dim_score = max(0, 100 - sum(penalty[f["severity"]] for f in mine))
        blocking = any(f["severity"] in ("critical", "high") for f in mine)
        status = "FAIL" if dim_score < 60 or (blocking and d["id"] in criteria["gating_dimensions"]) else "PASS"
        dims.append({"id": d["id"], "score": dim_score, "status": status, "findings": mine})

    overall = round(sum(d["score"] * c["weight"] for d, c in zip(dims, criteria["dimensions"])))
    failed = any(d["status"] == "FAIL" for d in dims)
    return {
        "verdict": "FAIL" if failed or overall < criteria["pass_score"] else "PASS",
        "score": overall,
        "dimensions": dims,
        "refuted_count": sum(1 for f in findings if f.get("verification") == "refuted"),
    }


def validate_verdict(v: dict) -> None:
    for key in ("verdict", "score", "dimensions"):
        if key not in v:
            raise EvalError(f"verdict missing '{key}'")
    if v["verdict"] not in ("PASS", "FAIL"):
        raise EvalError(f"verdict must be PASS or FAIL, got {v['verdict']}")


def call_api(url: str, payload: dict, token: str | None) -> dict:
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.load(resp)


def run(args: argparse.Namespace) -> dict:
    criteria = load_criteria(Path(args.criteria))
    identity = {"repo": args.repo, "commit": args.commit,
                "image_digest": args.digest, "release": args.release}

    if args.mode == "replay":
        result = json.loads(Path(args.fixture).read_text())
        validate_verdict(result)
    elif args.mode == "api":
        url = os.environ.get("EVAL_API_URL")
        if not url:
            raise EvalError("EVAL_API_URL is not set")
        result = call_api(url, identity, os.environ.get("EVAL_API_TOKEN"))
        validate_verdict(result)
    else:
        findings = []
        for path in args.findings or []:
            doc = json.loads(Path(path).read_text())
            findings.extend(doc["findings"] if isinstance(doc, dict) else doc)
        gt = json.loads(Path(args.ground_truth).read_text()) if args.ground_truth else {}
        result = score(criteria, findings + ground_truth_findings(gt))
        result["ground_truth"] = {k: v for k, v in gt.items() if k != "semgrep"}

    result.update(identity)
    result["eval_version"] = criteria["eval_version"]
    result["mode"] = args.mode
    result["report_url"] = args.report_url or result.get("report_url", "")
    return result


def write_outputs(result: dict, out: Path, env_out: Path | None) -> None:
    out.write_text(json.dumps(result, indent=2))
    compact = json.dumps({k: v for k, v in result.items() if k != "ground_truth"}, separators=(",", ":"))
    if len(compact) > 8000:
        raise EvalError("EVAL_JSON exceeds 8 KB; trim findings evidence")
    if env_out:
        env_out.write_text(
            f"EVAL_VERDICT={result['verdict']}\n"
            f"EVAL_SCORE={result['score']}\n"
            f"EVAL_REPORT_URL={result['report_url']}\n"
            f"EVAL_JSON={compact}\n"
        )


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--mode", choices=("live", "replay", "api"), default=os.getenv("EVAL_MODE", "live"))
    p.add_argument("--criteria", default=str(HERE / "criteria.yaml"))
    p.add_argument("--findings", nargs="*", help="agent findings JSON files")
    p.add_argument("--ground-truth", help="scanner and coverage summary JSON")
    p.add_argument("--fixture", default=str(HERE / "fixtures" / "verdict-pass.json"))
    p.add_argument("--repo", required=True)
    p.add_argument("--commit", required=True)
    p.add_argument("--digest", required=True)
    p.add_argument("--release", default="")
    p.add_argument("--report-url", default="")
    p.add_argument("--out", default="eval-result.json")
    p.add_argument("--env-out")
    args = p.parse_args(argv)
    try:
        result = run(args)
        write_outputs(result, Path(args.out), Path(args.env_out) if args.env_out else None)
    except (EvalError, OSError, ValueError, KeyError) as exc:
        # Fail closed: an unusable verdict is a FAIL with the reason recorded.
        result = {"verdict": "FAIL", "score": 0, "dimensions": [], "error": str(exc),
                  "repo": args.repo, "commit": args.commit, "image_digest": args.digest,
                  "mode": args.mode, "report_url": args.report_url}
        write_outputs(result, Path(args.out), Path(args.env_out) if args.env_out else None)
        print(f"eval-gate: {exc}", file=sys.stderr)
    print(json.dumps({k: result[k] for k in ("verdict", "score", "mode")}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
