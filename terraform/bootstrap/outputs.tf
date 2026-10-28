output "account_id" {
  description = "AWS account id of the lab this stack was applied in."
  value       = local.account_id
}

output "state_bucket" {
  description = "S3 bucket holding the foundation and cluster state; goes into each stack's backend.hcl."
  value       = awscc_s3_bucket.state.bucket_name
}
