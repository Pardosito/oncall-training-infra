terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Bootstrap creates the state bucket, so its own state stays local (D-02).
  # terraform.tfstate is gitignored; if it's lost, re-import the bucket.
  backend "local" {}
}
