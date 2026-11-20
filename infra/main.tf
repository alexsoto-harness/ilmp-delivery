# ILMP demo estate: one VPC, one Fargate cluster, one ALB.
#
# Shared infrastructure only. Harness CD owns ECS task definitions and
# services; a routine release never runs tofu apply. Listener rules used by
# blue/green stages ignore action changes because Harness shifts their weights.

locals {
  tags = {
    customer = "spdji"
    demo     = "ilmp"
    Owner    = "alex.soto"
    Customer = "spdji"
    Purpose  = "demo"
    Expires  = var.expires
  }

  # Rolling targets: one listener port per component and environment.
  rolling = {
    calc-dev = { port = 8081, health = "/health" }
    calc-qa  = { port = 8082, health = "/health" }
    calc-uat = { port = 8084, health = "/health" }
    svc-dev  = { port = 8091, health = "/actuator/health" }
    svc-qa   = { port = 8092, health = "/actuator/health" }
  }

  # Blue/green targets: a prod listener rule weighted across blue and green,
  # and a stage listener rule on green for pre-shift checks.
  bluegreen = {
    calc-qadr = { prod_port = 8083, stage_port = 9083 }
    calc-prod = { prod_port = 80, stage_port = 8080 }
  }

  bg_target_groups = merge([
    for k, _ in local.bluegreen : {
      "${k}-blue"  = k
      "${k}-green" = k
    }
  ]...)
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------------------------------------------------------- network

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ILMP demo ALB listeners"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each          = toset(var.ingress_cidrs)
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 9099
  description       = "Demo listeners 80, 8080-8099, 9083"
}

resource "aws_vpc_security_group_egress_rule" "alb" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.tasks.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "ILMP demo Fargate tasks"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_egress_rule" "tasks" {
  security_group_id = aws_security_group.tasks.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "ECR pulls and CloudWatch Logs over the internet gateway"
}

# ---------------------------------------------------------------- compute

resource "aws_ecs_cluster" "this" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.name}"
  retention_in_days = 14
}

resource "aws_iam_role" "task_execution" {
  name = "ilmp-ecs-task-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecr_repository" "component" {
  for_each             = toset(["calc-engine", "service-layer"])
  name                 = "ilmp/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "component" {
  for_each   = aws_ecr_repository.component
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 30 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }
      action       = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------- load balancer

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "rolling" {
  for_each             = local.rolling
  name                 = "ilmp-${each.key}"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.this.id
  deregistration_delay = 15
  health_check {
    path                = each.value.health
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 5
  }
}

resource "aws_lb_listener" "rolling" {
  for_each          = local.rolling
  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rolling[each.key].arn
  }
}

resource "aws_lb_target_group" "bluegreen" {
  for_each             = local.bg_target_groups
  name                 = "ilmp-${each.key}"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.this.id
  deregistration_delay = 15
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 5
  }
}

resource "aws_lb_listener" "bg_prod" {
  for_each          = local.bluegreen
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

resource "aws_lb_listener" "bg_stage" {
  for_each          = local.bluegreen
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

resource "aws_lb_listener_rule" "bg_prod" {
  for_each     = local.bluegreen
  listener_arn = aws_lb_listener.bg_prod[each.key].arn
  priority     = 10
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.bluegreen["${each.key}-blue"].arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.bluegreen["${each.key}-green"].arn
        weight = 0
      }
    }
  }
  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener_rule" "bg_stage" {
  for_each     = local.bluegreen
  listener_arn = aws_lb_listener.bg_stage[each.key].arn
  priority     = 10
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bluegreen["${each.key}-green"].arn
  }
  lifecycle {
    ignore_changes = [action]
  }
}
