# SPA site (D-31): S3 static website hosting instead of CloudFront, which the lab doesn't allow
# for this team. The website endpoint is HTTP only; the bucket's HTTPS REST endpoint serves the
# two tiny Cognito bounce pages (auth/callback.html, auth/signed-out.html), because Cognito only
# accepts HTTPS callback URLs (or localhost). The frontend uploads its build here.
# awscc, not aws_s3_bucket: the lab's SCP denies s3:GetBucketObjectLockConfiguration (D-24).
resource "awscc_s3_bucket" "site" {
  bucket_name = "${local.name}-site-${local.account_id}"

  website_configuration = {
    index_document = "index.html"
    # Deep links (/scenarios, /callback) get index.html and the SPA router takes over.
    error_document = "index.html"
  }

  # Public read is the point of a website bucket; only the policy below grants it.
  public_access_block_configuration = {
    block_public_acls       = true
    ignore_public_acls      = true
    block_public_policy     = false
    restrict_public_buckets = false
  }

  bucket_encryption = {
    server_side_encryption_configuration = [{
      server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }]
  }

  tags = local.awscc_tags
}

resource "aws_s3_bucket_policy" "site_public_read" {
  bucket = awscc_s3_bucket.site.bucket_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadSite"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${awscc_s3_bucket.site.arn}/*"
    }]
  })
}

locals {
  site_bucket       = awscc_s3_bucket.site.bucket_name
  site_website_url  = "http://${local.site_bucket}.s3-website-us-east-1.amazonaws.com"
  site_https_origin = "https://${local.site_bucket}.s3.us-east-1.amazonaws.com"
}
