terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # S3 buckets only: the lab blocks the object lock read aws_s3_bucket needs (D-24).
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.0"
    }
  }

  # Bootstrap creates the state bucket, so its own state stays local (D-02).
  # terraform.tfstate is gitignored; if it's lost, re-import the bucket.
  backend "local" {}
}
