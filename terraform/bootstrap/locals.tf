data "aws_caller_identity" "current" {}

locals {
  name       = "oncall-training"
  account_id = data.aws_caller_identity.current.account_id

  tags = {
    Project   = local.name
    Owner     = var.owner
    Env       = "lab"
    ManagedBy = "terraform"
    Stack     = "bootstrap"
  }
  awscc_tags = [for k, v in local.tags : { key = k, value = v }]
}
