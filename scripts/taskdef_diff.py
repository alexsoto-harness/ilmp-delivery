#!/usr/bin/env python3
"""Field-level diff of two ECS task definition manifests for ilmp_taskdef_guard.

Compares the manifest at the commit running in the target environment with the
one being released. Task definitions are immutable, so every release registers
a new revision; the guard therefore diffs attributes, not actions. The image is
always reported because every release changes it.

Usage: taskdef_diff.py OLD.yaml NEW.yaml --layer calc-engine --change-type routine
Prints the Policy step payload as JSON.
"""

import argparse
import json
import sys
from pathlib import Path

import yaml

IGNORED = {"tags"}


def flatten(node, prefix=""):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from flatten(v, f"{prefix}.{k}" if prefix else k)
    elif isinstance(node, list) and node and all(isinstance(i, dict) for i in node) and prefix.endswith("containerDefinitions"):
        for i, item in enumerate(node):
            yield from flatten(item, f"{prefix}[{i}]")
    else:
        yield prefix, node


def changed_fields(old: dict, new: dict) -> list[str]:
    a, b = dict(flatten(old)), dict(flatten(new))
    fields = {"containerDefinitions[0].image"}
    for key in a.keys() | b.keys():
        if key.split(".")[0] in IGNORED or key.endswith(".image"):
            continue
        if a.get(key) != b.get(key):
            # Report at the granularity the allowlist uses.
            parts = key.split(".")
            fields.add(".".join(parts[:2]) if parts[0].startswith("containerDefinitions") else parts[0])
    return sorted(fields)


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("old")
    p.add_argument("new")
    p.add_argument("--layer", required=True)
    p.add_argument("--change-type", default="routine")
    a = p.parse_args(argv)
    old_path = Path(a.old)
    old = yaml.safe_load(old_path.read_text()) if old_path.exists() else {}
    new = yaml.safe_load(Path(a.new).read_text())
    payload = {"layer": a.layer, "change_type": a.change_type,
               "changed_fields": changed_fields(old or new, new),
               "first_deploy": not old_path.exists()}
    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
