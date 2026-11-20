# Entity: Custom (Policy step before every ECS deploy). Harness version of
# tf-guard.sh mode=component: a routine release may change only the image.
# Payload: {layer, change_type, changed_fields: ["containerDefinitions[0].image", ...]}
package ilmp_taskdef_guard

allowlist := {
	"routine": {"containerDefinitions[0].image"},
	"emergency": {"containerDefinitions[0].image"},
	"platform": {
		"containerDefinitions[0].image",
		"containerDefinitions[0].environment",
		"cpu",
		"memory",
	},
}

deny[msg] {
	not allowlist[input.change_type]
	msg := sprintf("Unknown change_type %v", [input.change_type])
}

deny[msg] {
	allowed := allowlist[input.change_type]
	field := input.changed_fields[_]
	not allowed[field]
	msg := sprintf("%s: fields changed besides image: %s (change_type=%s)", [input.layer, field, input.change_type])
}
