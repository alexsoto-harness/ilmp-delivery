# Optional dedicated Harness delegate for ECS deploy steps, running as one
# Fargate task in the ILMP cluster. Off by default: enable it once a
# project-scoped delegate token exists and its value is set on the IaCM
# workspace as the secret variable delegate_token.

variable "enable_delegate" {
  type    = bool
  default = false
}

variable "delegate_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "delegate_image" {
  type    = string
  default = "harness/delegate:latest"
}

variable "harness_account_id" {
  type    = string
  default = "EeRjnXTnS4GrLG5VNNJZUw"
}

resource "aws_secretsmanager_secret" "delegate_token" {
  count                   = var.enable_delegate ? 1 : 0
  name                    = "ilmp/harness-delegate-token"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "delegate_token" {
  count         = var.enable_delegate ? 1 : 0
  secret_id     = aws_secretsmanager_secret.delegate_token[0].id
  secret_string = var.delegate_token
}

resource "aws_iam_role_policy" "task_execution_delegate_secret" {
  count = var.enable_delegate ? 1 : 0
  name  = "read-delegate-token"
  role  = aws_iam_role.task_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_secretsmanager_secret.delegate_token[0].arn
    }]
  })
}

resource "aws_ecs_task_definition" "delegate" {
  count                    = var.enable_delegate ? 1 : 0
  family                   = "ilmp-harness-delegate"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.task_execution.arn
  container_definitions = jsonencode([{
    name      = "delegate"
    image     = var.delegate_image
    essential = true
    environment = [
      { name = "ACCOUNT_ID", value = var.harness_account_id },
      { name = "MANAGER_HOST_AND_PORT", value = "https://app.harness.io" },
      { name = "LOG_STREAMING_SERVICE_URL", value = "https://app.harness.io/log-service/" },
      { name = "DELEGATE_NAME", value = "ilmp-ecs-delegate" },
      { name = "DELEGATE_TYPE", value = "DOCKER" },
      { name = "DELEGATE_TAGS", value = "ilmp-ecs-delegate" },
      { name = "NEXT_GEN", value = "true" },
      { name = "DELEGATE_ORG_IDENTIFIER", value = "sandbox" },
      { name = "DELEGATE_PROJECT_IDENTIFIER", value = "soto_sandbox" },
    ]
    secrets = [{ name = "DELEGATE_TOKEN", valueFrom = aws_secretsmanager_secret.delegate_token[0].arn }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "delegate"
      }
    }
  }])
}

resource "aws_ecs_service" "delegate" {
  count           = var.enable_delegate ? 1 : 0
  name            = "ilmp-harness-delegate"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.delegate[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }
}
