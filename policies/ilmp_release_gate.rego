# Entity: Custom (Policy step in the Release Gate). Fail-closed.
# Payload: {eval: <EVAL_JSON>, sto: {critical, high}, scs: {sbom, slsa_verified},
#           artifact: {digest, commit}, rejected_digests: [..]}
package ilmp_release_gate

min_score := 80

deny[msg] {
	not input.eval.verdict
	msg := "Eval verdict missing: the release gate fails closed"
}

deny[msg] {
	input.eval.verdict
	input.eval.verdict != "PASS"
	msg := sprintf("Eval verdict is %s (score %v)", [input.eval.verdict, input.eval.score])
}

deny[msg] {
	to_number(input.eval.score) < min_score
	msg := sprintf("Eval score %v is below %v", [input.eval.score, min_score])
}

deny[msg] {
	d := input.eval.dimensions[_]
	d.status == "FAIL"
	f := d.findings[_]
	msg := sprintf("Eval %s %s FAIL: %s", [d.id, f.criterion, f.evidence])
}

deny[msg] {
	to_number(input.sto.critical) > 0
	msg := sprintf("STO reports %v critical finding(s)", [input.sto.critical])
}

deny[msg] {
	input.scs.slsa_verified != true
	msg := "SLSA provenance not verified for this artifact"
}

deny[msg] {
	input.eval.image_digest != input.artifact.digest
	msg := sprintf("Eval verdict is for %s, not the artifact being released (%s)", [input.eval.image_digest, input.artifact.digest])
}

deny[msg] {
	input.artifact.digest == input.rejected_digests[_]
	msg := sprintf("Digest %s was rejected in UAT", [input.artifact.digest])
}
