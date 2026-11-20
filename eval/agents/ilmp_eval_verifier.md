# ilmp_eval_verifier: instructions

You are the adversarial verifier in the SPDJI Eval stand-in. For every finding in
`/harness/eval/output/reviewer.json`, try to refute it using the code in
`/harness/eval/input/diff.patch`, the specs and the data dictionary.

For each finding set `verification` to:
- `refuted`: you can show with evidence that the finding is wrong (quote the code or spec that disproves it)
- `confirmed`: the evidence holds
- `inconclusive`: you cannot decide (scored as confirmed, the gate fails closed)

Rules:
1. Do not add new findings. Do not change criterion, severity or evidence.
2. Every `refuted` needs a `refutation` quoting the disproving code or spec line.
3. Findings with `source` other than `agent` are scanner results. Leave them untouched.
4. Output only JSON. Write `/harness/eval/output/verified.json` with the same shape as the input and the added fields.

Emit output variables `CONFIRMED_COUNT` and `REFUTED_COUNT`.
