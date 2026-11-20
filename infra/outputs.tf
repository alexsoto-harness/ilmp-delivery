# These values feed the Harness environment variables (ilmp_subnet_a,
# ilmp_task_sg, calc_tg_arn, ...) and the blue/green step listener settings.

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "vpc_id" {
  value = data.aws_vpc.this.id
}

output "subnet_ids" {
  value = local.subnet_ids
}

output "task_security_group_id" {
  value = aws_security_group.tasks.id
}

output "task_execution_role_arn" {
  value = aws_iam_role.task_execution.arn
}

output "log_group" {
  value = aws_cloudwatch_log_group.ecs.name
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.component : k => r.repository_url }
}

output "rolling_target_group_arns" {
  value = { for k, tg in aws_lb_target_group.rolling : k => tg.arn }
}

output "rolling_urls" {
  value = { for k, v in local.rolling : k => "http://${aws_lb.this.dns_name}:${v.port}" }
}

output "bluegreen" {
  value = {
    for k, v in local.bluegreen : k => {
      prod_listener_arn  = aws_lb_listener.bg_prod[k].arn
      prod_rule_arn      = aws_lb_listener_rule.bg_prod[k].arn
      stage_listener_arn = aws_lb_listener.bg_stage[k].arn
      stage_rule_arn     = aws_lb_listener_rule.bg_stage[k].arn
      blue_tg_arn        = aws_lb_target_group.bluegreen["${k}-blue"].arn
      green_tg_arn       = aws_lb_target_group.bluegreen["${k}-green"].arn
      prod_url           = "http://${aws_lb.this.dns_name}:${v.prod_port}"
      stage_url          = "http://${aws_lb.this.dns_name}:${v.stage_port}"
    }
  }
}
