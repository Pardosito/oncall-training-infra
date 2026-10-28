provider "aws" {
  # Learner Lab only allows us-east-1 (AGENTS §4).
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = local.name
      Owner     = var.owner
      Env       = "lab"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
