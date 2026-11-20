variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "ilmp-demo"
}

variable "vpc_cidr" {
  description = "Unused when use_default_vpc=true; retained for talk-track parity with a dedicated CIDR."
  type        = string
  default     = "10.42.0.0/16"
}

variable "use_default_vpc" {
  description = "Reuse the account default VPC to avoid VpcLimitExceeded."
  type        = bool
  default     = true
}

variable "expires" {
  description = "Teardown date for the demo estate (demo date + 14 days)."
  type        = string
  default     = "2026-12-31"
}

variable "ingress_cidrs" {
  description = "Who may reach the demo ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
