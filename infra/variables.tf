variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "ilmp-demo"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
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
