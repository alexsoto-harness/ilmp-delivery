import json
import sys
from pathlib import Path

import pytest

EVAL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL))

import eval_gate  # noqa: E402

CRITERIA = eval_gate.load_criteria(EVAL / "criteria.yaml")
IDENT = ["--repo", "ilmp-calc-engine", "--commit", "abc1234", "--digest", "sha256:aaa"]


def run(tmp_path, *extra):
    out, env = tmp_path / "out.json", tmp_path / "out.env"
    eval_gate.main([*IDENT, "--out", str(out), "--env-out", str(env), *extra])
    return json.loads(out.read_text()), env.read_text()


def test_clean_change_passes():
    assert eval_gate.score(CRITERIA, [])["verdict"] == "PASS"


def test_refuted_findings_do_not_count():
    f = {"criterion": "A1", "severity": "high", "evidence": "x", "verification": "refuted"}
    result = eval_gate.score(CRITERIA, [f])
    assert result["verdict"] == "PASS"
    assert result["refuted_count"] == 1


def test_inconclusive_counts_as_confirmed():
    f = {"criterion": "A1", "severity": "high", "evidence": "x", "verification": "inconclusive"}
    assert eval_gate.score(CRITERIA, [f])["verdict"] == "FAIL"


def test_high_in_gating_dimension_fails():
    f = {"criterion": "S3", "severity": "high", "evidence": "yaml.load", "verification": "confirmed"}
    result = eval_gate.score(CRITERIA, [f])
    sec = next(d for d in result["dimensions"] if d["id"] == "security")
    assert sec["status"] == "FAIL" and result["verdict"] == "FAIL"


def test_medium_findings_lower_score_without_failing():
    fs = [{"criterion": "U2", "severity": "medium", "evidence": "x", "verification": "confirmed"}]
    result = eval_gate.score(CRITERIA, fs)
    assert result["verdict"] == "PASS" and result["score"] < 100


def test_unknown_criterion_rejected():
    with pytest.raises(eval_gate.EvalError):
        eval_gate.score(CRITERIA, [{"criterion": "Z9", "severity": "low", "evidence": "x"}])


def test_live_mode_imports_semgrep_as_preconfirmed(tmp_path):
    gt = tmp_path / "gt.json"
    gt.write_text(json.dumps({"sto_critical": 0, "sto_high": 0, "semgrep": [
        {"criterion": "A1", "evidence": "app/jobs.py:66 INSERT INTO pricing.ref_rates"}]}))
    result, env = run(tmp_path, "--mode", "live", "--ground-truth", str(gt))
    assert result["verdict"] == "FAIL"
    assert "EVAL_VERDICT=FAIL" in env
    arch = next(d for d in result["dimensions"] if d["id"] == "architecture")
    assert arch["findings"][0]["verification"] == "pre-confirmed"


def test_replay_binds_to_current_artifact(tmp_path):
    result, env = run(tmp_path, "--mode", "replay")
    assert result["image_digest"] == "sha256:aaa" and result["mode"] == "replay"
    assert "EVAL_SCORE=91" in env


def test_api_mode_without_url_fails_closed(tmp_path, monkeypatch):
    monkeypatch.delenv("EVAL_API_URL", raising=False)
    result, env = run(tmp_path, "--mode", "api")
    assert result["verdict"] == "FAIL" and "EVAL_API_URL" in result["error"]


def test_bad_agent_output_fails_closed(tmp_path):
    bad = tmp_path / "findings.json"
    bad.write_text('{"findings": [{"criterion": "A1"}]}')
    result, _ = run(tmp_path, "--mode", "live", "--findings", str(bad))
    assert result["verdict"] == "FAIL" and "missing" in result["error"]
