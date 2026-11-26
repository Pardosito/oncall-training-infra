data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Zone names map to different physical zones in each account, so the zones are picked by ID.
# use1-az3 has no API Gateway VPC links and no EKS control plane (D-33).
data "aws_availability_zones" "this" {
  state            = "available"
  exclude_zone_ids = ["use1-az3"]
}

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
  api_port = 3000 # backend-api container port (k8s/base/app)
  azs      = slice(sort(data.aws_availability_zones.this.names), 0, 2)
  # 10.20.0.0/20 and 10.20.16.0/20: nodes and pods.
  public_subnets = { for i, az in local.azs : az => cidrsubnet(local.vpc_cidr, 4, i) }
  # 10.20.128.0/24 and 10.20.129.0/24, no internet route: the internal ALB, the VPC link and
  # ElastiCache (INF-053, D-33).
  private_subnets = { for i, az in local.azs : az => cidrsubnet(local.vpc_cidr, 8, 128 + i) }

  tags = {
    Project   = local.name
    Owner     = var.owner
    Env       = "lab"
    ManagedBy = "terraform"
    Stack     = "cluster"
  }
}
