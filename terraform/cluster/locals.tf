data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Every role argument uses LabRole; the lab forbids creating IAM roles (AGENTS §4).
data "aws_iam_role" "lab" {
  name = "LabRole"
}

locals {
  name   = "oncall-training"
  region = data.aws_region.current.region

  # The role behind the lab session (voclabs), parsed from the assumed-role caller ARN:
  #   arn:aws:sts::<acct>:assumed-role/voclabs/<session> → arn:aws:iam::<acct>:role/voclabs
  # Not data "aws_iam_session_context": it calls iam:GetRole, which the lab denies on voclabs (D-26).
  caller_role       = regex("^arn:aws:sts::([0-9]+):assumed-role/([^/]+)/", data.aws_caller_identity.current.arn)
  lab_principal_arn = "arn:aws:iam::${local.caller_role[0]}:role/${local.caller_role[1]}"

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
