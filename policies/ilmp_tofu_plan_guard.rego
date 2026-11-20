# Entity: Terraform Plan (IaCM, evaluated after every plan of ilmp_demo_estate).
# FR-007 never destroy, plus a resource-type allowlist for the shared estate.
package ilmp_tofu_plan_guard

protected := {
	"aws_ecs_cluster",
	"aws_ecs_service",
	"aws_lb",
	"aws_lb_listener",
	"aws_lb_listener_rule",
	"aws_lb_target_group",
	"aws_ecr_repository",
	"aws_vpc",
	"aws_subnet",
	"aws_cloudwatch_event_rule",
	"aws_cloudwatch_event_target",
	"aws_sfn_state_machine",
}

allowed_types := protected | {
	"aws_internet_gateway",
	"aws_route_table",
	"aws_route_table_association",
	"aws_security_group",
	"aws_vpc_security_group_ingress_rule",
	"aws_vpc_security_group_egress_rule",
	"aws_ecs_cluster_capacity_providers",
	"aws_cloudwatch_log_group",
	"aws_iam_role",
	"aws_iam_role_policy_attachment",
	"aws_ecr_lifecycle_policy",
	"aws_iam_role_policy",
	"aws_secretsmanager_secret",
	"aws_secretsmanager_secret_version",
	"aws_ecs_task_definition",
}

# The policy set is project-wide; only plans of this estate are in scope.
ilmp_estate {
	input.variables.name.value == "ilmp-demo"
}

deny[msg] {
	ilmp_estate
	rc := input.resource_changes[_]
	protected[rc.type]
	rc.change.actions[_] == "delete"
	msg := sprintf("FR-007 never destroy: %s %v", [rc.address, rc.change.actions])
}

deny[msg] {
	ilmp_estate
	rc := input.resource_changes[_]
	rc.mode == "managed"
	not allowed_types[rc.type]
	rc.change.actions[_] != "no-op"
	msg := sprintf("%s is outside the ilmp_demo_estate allowlist", [rc.address])
}
