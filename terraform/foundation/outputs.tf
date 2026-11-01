# Contract outputs (ARCHITECTURE §3): the cluster stack, scripts and other repos' CI use them.
# Renaming one is a contract change.

output "account_id" {
  description = "AWS account id of the lab this stack was applied in."
  value       = local.account_id
}

output "sessions_table" {
  description = "DynamoDB table name for sessions (backend SESSIONS_TABLE)."
  value       = aws_dynamodb_table.sessions.name
}

output "files_bucket" {
  description = "S3 bucket for scenario files, session logs and Athena results (backend FILES_BUCKET)."
  value       = awscc_s3_bucket.files.bucket_name
}

output "faults_queue_url" {
  description = "SQS faults queue URL (injector and, in the MVP, backend FAULTS_QUEUE_URL)."
  value       = module.faults.url
}

output "faults_dlq_url" {
  description = "Dead-letter queue for faults the injector couldn't handle."
  value       = module.faults.dlq_url
}

output "user_actions_queue_url" {
  description = "SQS user-actions FIFO queue URL (backend USER_ACTIONS_QUEUE_URL)."
  value       = module.user_actions.url
}

output "user_actions_dlq_url" {
  description = "Dead-letter queue for user actions the worker couldn't handle."
  value       = module.user_actions.dlq_url
}

output "ecr_repository_urls" {
  description = "ECR repository URL per image: backend, injector, mock-system."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
