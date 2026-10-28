# Remote state for the foundation and cluster stacks (ARCHITECTURE §2).
# S3 native locking (use_lockfile) needs no DynamoDB table.
# awscc, not aws_s3_bucket: the lab's SCP denies s3:GetBucketObjectLockConfiguration (D-24).
resource "awscc_s3_bucket" "state" {
  bucket_name = "${local.name}-tfstate-${local.account_id}"

  versioning_configuration = {
    status = "Enabled"
  }

  bucket_encryption = {
    server_side_encryption_configuration = [{
      server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }]
  }

  public_access_block_configuration = {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }

  tags = local.awscc_tags

  lifecycle {
    prevent_destroy = true
  }
}
