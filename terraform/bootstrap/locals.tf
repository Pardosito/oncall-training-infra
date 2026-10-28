data "aws_caller_identity" "current" {}

locals {
  name       = "oncall-training"
  account_id = data.aws_caller_identity.current.account_id
}
