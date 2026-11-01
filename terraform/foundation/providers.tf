# Learner Lab only allows us-east-1 (AGENTS §4).

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

# awscc has no default_tags; pass local.awscc_tags to each resource.
provider "awscc" {
  region = "us-east-1"
}
