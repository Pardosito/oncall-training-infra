# Files bucket (ARCHITECTURE §3): scenario files, session logs for Athena, Athena results.
# awscc, not aws_s3_bucket: the lab's SCP denies s3:GetBucketObjectLockConfiguration (D-24).
resource "awscc_s3_bucket" "files" {
  bucket_name = "${local.name}-files-${local.account_id}"

  # Versioning stays off: logs are append-only and Athena results are throwaway.

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

  lifecycle_configuration = {
    rules = [{
      id                 = "expire-athena-results"
      status             = "Enabled"
      prefix             = "athena-results/"
      expiration_in_days = 7
    }]
  }

  tags = local.awscc_tags

  lifecycle {
    prevent_destroy = true
  }
}
