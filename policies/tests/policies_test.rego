package ilmp_policies_test

import data.ilmp_prod_requires_change
import data.ilmp_release_gate
import data.ilmp_sbom_denylist
import data.ilmp_slsa_provenance
import data.ilmp_taskdef_guard
import data.ilmp_tofu_plan_guard

pass_eval := {
	"verdict": "PASS", "score": 91, "image_digest": "sha256:aaa",
	"dimensions": [{"id": "security", "status": "PASS", "findings": []}],
}

gate_input(eval) := {
	"eval": eval,
	"sto": {"critical": 0, "high": 1},
	"scs": {"sbom": true, "slsa_verified": true},
	"artifact": {"digest": "sha256:aaa", "commit": "abc"},
	"rejected_digests": [],
}

test_gate_allows_pass {
	count(ilmp_release_gate.deny) == 0 with input as gate_input(pass_eval)
}

test_gate_fails_closed_without_verdict {
	ilmp_release_gate.deny["Eval verdict missing: the release gate fails closed"] with input as gate_input({})
}

test_gate_denies_failing_dimension {
	eval := json.patch(pass_eval, [
		{"op": "replace", "path": "/verdict", "value": "FAIL"},
		{"op": "replace", "path": "/score", "value": 72},
		{"op": "replace", "path": "/dimensions", "value": [{"id": "architecture", "status": "FAIL", "findings": [{"criterion": "A1", "evidence": "app/jobs.py INSERT INTO pricing.ref_rates"}]}]},
	])
	ilmp_release_gate.deny["Eval architecture A1 FAIL: app/jobs.py INSERT INTO pricing.ref_rates"] with input as gate_input(eval)
	ilmp_release_gate.deny["Eval score 72 is below 80"] with input as gate_input(eval)
}

test_gate_binds_verdict_to_digest {
	eval := json.patch(pass_eval, [{"op": "replace", "path": "/image_digest", "value": "sha256:bbb"}])
	count(ilmp_release_gate.deny) == 1 with input as gate_input(eval)
}

test_gate_denies_rejected_digest {
	inp := json.patch(gate_input(pass_eval), [{"op": "replace", "path": "/rejected_digests", "value": ["sha256:aaa"]}])
	ilmp_release_gate.deny["Digest sha256:aaa was rejected in UAT"] with input as inp
}

test_taskdef_allows_image_only {
	count(ilmp_taskdef_guard.deny) == 0 with input as {"layer": "calc-engine", "change_type": "routine", "changed_fields": ["containerDefinitions[0].image"]}
}

test_taskdef_refuses_environment_change {
	ilmp_taskdef_guard.deny["ui: fields changed besides image: containerDefinitions[0].environment (change_type=routine)"] with input as {"layer": "ui", "change_type": "routine", "changed_fields": ["containerDefinitions[0].image", "containerDefinitions[0].environment"]}
}

test_plan_guard_refuses_delete {
	ilmp_tofu_plan_guard.deny["FR-007 never destroy: aws_lb.this [\"delete\", \"create\"]"] with input as {"resource_changes": [{"address": "aws_lb.this", "type": "aws_lb", "mode": "managed", "change": {"actions": ["delete", "create"]}}]}
}

test_plan_guard_refuses_unlisted_type {
	count(ilmp_tofu_plan_guard.deny) == 1 with input as {"resource_changes": [{"address": "aws_db_instance.x", "type": "aws_db_instance", "mode": "managed", "change": {"actions": ["create"]}}]}
}

test_plan_guard_allows_update {
	count(ilmp_tofu_plan_guard.deny) == 0 with input as {"resource_changes": [{"address": "aws_lb_target_group.rolling", "type": "aws_lb_target_group", "mode": "managed", "change": {"actions": ["update"]}}]}
}

prod_stage(steps, rollback) := {"stage": {
	"identifier": "prod", "name": "Prod", "type": "Deployment",
	"spec": {"environment": {"environmentRef": "ilmp_prod"}, "execution": {"steps": steps, "rollbackSteps": rollback}},
}}

good_steps := [
	{"step": {"identifier": "approve", "type": "HarnessApproval"}},
	{"step": {"identifier": "bg", "type": "EcsBlueGreenCreateService"}},
	{"step": {"identifier": "verify_version", "type": "Http"}},
]

rb := [{"step": {"identifier": "rb", "type": "EcsBlueGreenRollback"}}]

test_prod_policy_allows_complete_stage {
	count(ilmp_prod_requires_change.deny) == 0 with input as {"pipeline": {"stages": [prod_stage(good_steps, rb)]}}
}

test_prod_policy_denies_missing_approval {
	ilmp_prod_requires_change.deny["Prod stage 'Prod' has no approval or change record step"] with input as {"pipeline": {"stages": [prod_stage([good_steps[1], good_steps[2]], rb)]}}
}

test_prod_policy_sees_step_groups {
	grouped := [{"stepGroup": {"identifier": "g", "steps": good_steps}}]
	count(ilmp_prod_requires_change.deny) == 0 with input as {"pipeline": {"stages": [prod_stage(grouped, rb)]}}
}

test_sbom_denies_pyyaml {
	ilmp_sbom_denylist.deny["Denied package PyYAML 5.3.1"] with input as [{"packageName": "PyYAML", "packageVersion": "5.3.1", "packageLicense": ["MIT"]}]
}

test_slsa_allows_release_build {
	count(ilmp_slsa_provenance.deny) == 0 with input as {"predicate": {
		"buildDefinition": {"externalParameters": {"codeMetadata": {"repositoryURL": "https://github.com/alexsoto-harness/ilmp-calc-engine", "branch": "release/2026.12"}}},
		"runDetails": {"builder": {"id": "https://developer.harness.io/docs/continuous-integration"}},
	}}
}

test_slsa_denies_feature_branch {
	count(ilmp_slsa_provenance.deny) == 1 with input as {"predicate": {
		"buildDefinition": {"externalParameters": {"codeMetadata": {"repositoryURL": "https://github.com/alexsoto-harness/ilmp-calc-engine", "branch": "feature/x"}}},
		"runDetails": {"builder": {"id": "https://developer.harness.io/docs/continuous-integration"}},
	}}
}
