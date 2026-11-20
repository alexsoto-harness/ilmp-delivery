# ilmp-delivery

Delivery tooling for the ILMP Index Studio demo (Harness for S&P DJI). This is the analogue of SPDJI's `ilmp-pipeline-utils`: one place for the pipelines, templates, policies and infrastructure that the component repos share.

| Path | What |
|---|---|
| `.harness/` | GitX entities: pipelines, templates, services, environments, infrastructure definitions, input sets |
| `infra/` | OpenTofu for the shared demo estate (IaCM workspace `ilmp_demo_estate`) |
| `policies/` | OPA policies with unit tests (`opa test policies`) |
| `eval/` | SPDJI Eval stand-in: criteria, deterministic scoring, agent instructions, Semgrep rules, fixtures |
| `scripts/` | Smoke backtest (FR-009), version verify (FR-008), task definition diff for the taskdef guard |

Component repos: [ilmp-calc-engine](https://github.com/alexsoto-harness/ilmp-calc-engine), [ilmp-service-layer](https://github.com/alexsoto-harness/ilmp-service-layer).

## Design in one paragraph

A merge to `release/*` in a component repo starts `ILMP Release`. Harness builds the image once, pushes the same digest to HAR (the record) and ECR (what ECS pulls), scans it, and runs the Eval stand-in. The release gate policy decides promotion from the Eval verdict, STO counts and SLSA result. The digest then moves through Dev, QA, QADR, UAT and Prod. Harness CD owns the ECS task definition, so a routine deploy never runs `tofu apply`; the taskdef guard policy refuses anything but an image change. After every deploy the pipeline asserts `/version` reports the deployed digest and task definition revision (FR-008) and runs a real backtest (FR-009). Shared infrastructure changes only through IaCM: plan, plan guard policy, approval, apply.

## Eval stand-in

The SPDJI Eval framework (10 dimensions, 93 criteria) runs here as their criteria in a Harness Worker Agent, with an API mode that accepts their contract later. The LLM never decides the verdict:

1. Ground truth from scanners (STO, Gitleaks, Semgrep architecture rules, coverage) enters as pre-confirmed findings.
2. `ilmp_eval_reviewer` proposes findings; `ilmp_eval_verifier` tries to refute each one. Inconclusive counts as confirmed.
3. `eval/eval_gate.py` scores with fixed weights and writes `EVAL_JSON`, `EVAL_VERDICT`, `EVAL_SCORE`.
4. `EVAL_MODE=api` POSTs `{repo, commit, image_digest, release}` to `EVAL_API_URL`; `replay` loads a recorded verdict.

```bash
pip install pyyaml pytest
pytest eval/tests scripts/tests
opa test policies
tofu -chdir=infra init -backend=false && tofu -chdir=infra validate
```

## Estate (`infra/`)

One VPC (two public subnets, no NAT), one Fargate cluster `ilmp-demo`, one ALB `ilmp-demo-alb`, log group `/ecs/ilmp-demo`, task execution role, ECR repos `ilmp/calc-engine` and `ilmp/service-layer`. Each environment gets a listener port:

| Target | Port | Strategy |
|---|---|---|
| calc engine Dev / QA / UAT | 8081 / 8082 / 8084 | rolling |
| calc engine QADR | 8083 (stage 9083) | blue/green |
| calc engine Prod | 80 (stage 8080) | blue/green traffic shift |
| service layer Dev / QA | 8091 / 8092 | rolling |

An optional dedicated Harness delegate (`enable_delegate`) runs as one Fargate task for ECS deploy steps.
