# Release manifests

One file per release, `releases/<release>.yaml` (for example `2026.12.yaml`). `ILMP Build` writes its component's entry after the build and the Eval gate; `ILMP Deploy` reads the file, refuses anything that is not a PASS bound to a digest, and promotes both components together.

The file is the record of what a release contains. `git log releases/2026.12.yaml` is the release history, including a rejected digest that was replaced by a later build.

Fields per component: `image`, `tag`, `digest`, `commit`, `build_url`, `eval_verdict`, `eval_score`, `recorded_at`. Written only by `scripts/record_release.py`; read by `scripts/resolve-release.sh`.
