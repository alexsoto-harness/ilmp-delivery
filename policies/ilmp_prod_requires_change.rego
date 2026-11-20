# Entity: Pipeline (On Save and On Run). Scenario S6.
# A Prod deploy stage must have an approval (Harness or ServiceNow) before the
# deploy, a progressive ECS strategy, a /version verify step, and a rollback.
package ilmp_prod_requires_change

approval_types := {"HarnessApproval", "ServiceNowApproval", "ServiceNowCreate"}

deploy_types := {"EcsBlueGreenCreateService", "EcsCanaryDeploy", "EcsBlueGreenSwapTargetGroups", "EcsBlueGreenTrafficShift"}

# The policy set is project-wide; only ILMP pipelines are in scope.
ilmp_pipeline {
	input.pipeline.tags.demo == "ilmp"
}

prod_stages[stage] {
	ilmp_pipeline
	stage := input.pipeline.stages[_].stage
	is_prod(stage)
}

prod_stages[stage] {
	ilmp_pipeline
	stage := input.pipeline.stages[_].parallel[_].stage
	is_prod(stage)
}

is_prod(stage) {
	stage.type == "Deployment"
	stage.spec.environment.environmentRef == "ilmp_prod"
}

is_prod(stage) {
	stage.type == "Deployment"
	contains(lower(stage.identifier), "prod")
}

steps(stage) := {s |
	walk(stage.spec.execution.steps, [_, s])
	is_object(s)
	s.type
}

rollback_steps(stage) := {s |
	walk(object.get(stage.spec.execution, "rollbackSteps", []), [_, s])
	is_object(s)
	s.type
}

deny[msg] {
	stage := prod_stages[_]
	count({s | s := steps(stage)[_]; approval_types[s.type]}) == 0
	msg := sprintf("Prod stage '%s' has no approval or change record step", [stage.name])
}

deny[msg] {
	stage := prod_stages[_]
	count({s | s := steps(stage)[_]; deploy_types[s.type]}) == 0
	msg := sprintf("Prod stage '%s' must deploy blue/green or canary", [stage.name])
}

deny[msg] {
	stage := prod_stages[_]
	count({s | s := steps(stage)[_]; contains(lower(s.identifier), "verify_version")}) == 0
	msg := sprintf("Prod stage '%s' has no verify_version step (FR-008)", [stage.name])
}

deny[msg] {
	stage := prod_stages[_]
	count(rollback_steps(stage)) == 0
	msg := sprintf("Prod stage '%s' has no rollback steps", [stage.name])
}
