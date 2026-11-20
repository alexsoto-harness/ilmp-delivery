import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from taskdef_diff import changed_fields  # noqa: E402

BASE = {
    "family": "ilmp-calc-engine-dev",
    "cpu": "256",
    "containerDefinitions": [{
        "name": "calc-engine",
        "image": "<+artifact.image>",
        "environment": [{"name": "ENVIRONMENT", "value": "dev"}],
    }],
    "tags": [{"key": "demo", "value": "ilmp"}],
}


def test_image_only_release():
    assert changed_fields(BASE, BASE) == ["containerDefinitions[0].image"]


def test_environment_change_is_reported():
    new = {**BASE, "containerDefinitions": [{**BASE["containerDefinitions"][0],
                                              "environment": [{"name": "FAIL_SMOKE", "value": "true"}]}]}
    assert "containerDefinitions[0].environment" in changed_fields(BASE, new)


def test_cpu_change_is_reported_and_tags_ignored():
    new = {**BASE, "cpu": "512", "tags": []}
    assert changed_fields(BASE, new) == ["containerDefinitions[0].image", "cpu"]
