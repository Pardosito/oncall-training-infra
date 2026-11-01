data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Every role argument uses LabRole; the lab forbids creating IAM roles (AGENTS §4).
data "aws_iam_role" "lab" {
  name = "LabRole"
}

# The role behind the current lab session (voclabs), from the assumed-role caller ARN.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  name   = "oncall-training"
  region = data.aws_region.current.region

  vpc_cidr = "10.20.0.0/16"
  public_subnets = {
    "us-east-1a" = "10.20.0.0/20"
    "us-east-1b" = "10.20.16.0/20"
  }

  tags = {
    Project   = local.name
    Owner     = var.owner
    Env       = "lab"
    ManagedBy = "terraform"
    Stack     = "cluster"
  }
}
