# Service-layer targets so both components promote through every environment.
# UAT is rolling; QADR and Prod are blue/green, like the calc engine. Prod and
# stage listeners get their own ports so the calc-engine listener rules stay put.

locals {
  svc_rolling_extra = {
    svc-uat = { port = 8094, health = "/actuator/health" }
  }

  svc_bluegreen = {
    svc-qadr = { prod_port = 8093, stage_port = 9093, health = "/actuator/health", traffic_shift = false }
    svc-prod = { prod_port = 8095, stage_port = 9095, health = "/actuator/health", traffic_shift = true }
  }

  svc_bg_target_groups = merge([
    for k, _ in local.svc_bluegreen : {
      "${k}-blue"  = k
      "${k}-green" = k
    }
  ]...)
}

resource "aws_lb_target_group" "svc_rolling_extra" {
  for_each             = local.svc_rolling_extra
  name                 = "ilmp-${each.key}"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.this.id
  deregistration_delay = 15
  health_check {
    path                = each.value.health
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 5
  }
}

resource "aws_lb_listener" "svc_rolling_extra" {
  for_each          = local.svc_rolling_extra
  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc_rolling_extra[each.key].arn
  }
}

resource "aws_lb_target_group" "svc_bluegreen" {
  for_each             = local.svc_bg_target_groups
  name                 = "ilmp-${each.key}"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.this.id
  deregistration_delay = 15
  health_check {
    path                = local.svc_bluegreen[each.value].health
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 5
  }
}

resource "aws_lb_listener" "svc_bg_prod" {
  for_each          = local.svc_bluegreen
  load_balancer_arn = aws_lb.this.arn
  port              = each.value.prod_port
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "no matching rule"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "svc_bg_stage" {
  for_each          = local.svc_bluegreen
  load_balancer_arn = aws_lb.this.arn
  port              = each.value.stage_port
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "no matching rule"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "svc_bg_prod" {
  for_each     = local.svc_bluegreen
  listener_arn = aws_lb_listener.svc_bg_prod[each.key].arn
  priority     = 10
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  # Same constraint as the calc-engine prod rules: QADR needs one target group.
  dynamic "action" {
    for_each = each.value.traffic_shift ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.svc_bluegreen["${each.key}-blue"].arn
    }
  }
  dynamic "action" {
    for_each = each.value.traffic_shift ? [1] : []
    content {
      type = "forward"
      forward {
        target_group {
          arn    = aws_lb_target_group.svc_bluegreen["${each.key}-blue"].arn
          weight = 100
        }
        target_group {
          arn    = aws_lb_target_group.svc_bluegreen["${each.key}-green"].arn
          weight = 0
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener_rule" "svc_bg_stage" {
  for_each     = local.svc_bluegreen
  listener_arn = aws_lb_listener.svc_bg_stage[each.key].arn
  priority     = 10
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc_bluegreen["${each.key}-green"].arn
  }
  lifecycle {
    ignore_changes = [action]
  }
}

output "svc_extra_rolling" {
  value = {
    for k, v in local.svc_rolling_extra : k => {
      target_group_arn = aws_lb_target_group.svc_rolling_extra[k].arn
      url              = "http://${aws_lb.this.dns_name}:${v.port}"
    }
  }
}

output "svc_bluegreen" {
  value = {
    for k, v in local.svc_bluegreen : k => {
      prod_listener_arn  = aws_lb_listener.svc_bg_prod[k].arn
      prod_rule_arn      = aws_lb_listener_rule.svc_bg_prod[k].arn
      stage_listener_arn = aws_lb_listener.svc_bg_stage[k].arn
      stage_rule_arn     = aws_lb_listener_rule.svc_bg_stage[k].arn
      blue_tg_arn        = aws_lb_target_group.svc_bluegreen["${k}-blue"].arn
      green_tg_arn       = aws_lb_target_group.svc_bluegreen["${k}-green"].arn
      prod_url           = "http://${aws_lb.this.dns_name}:${v.prod_port}"
      stage_url          = "http://${aws_lb.this.dns_name}:${v.stage_port}"
    }
  }
}
