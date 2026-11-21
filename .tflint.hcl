# tflint config for every Terraform directory (scripts/lint-tf.sh passes it with --config).
# `tflint --init --config .tflint.hcl` downloads the AWS ruleset.

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
