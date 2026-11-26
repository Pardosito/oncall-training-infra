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

output "state_machine_arn" {
  description = "Scenario state machine ARN (backend STATE_MACHINE_ARN, used when ORCHESTRATION_MODE=stepfunctions)."
  value       = aws_sfn_state_machine.scenario.arn
}

output "cognito_user_pool_id" {
  description = "Cognito user pool id (backend COGNITO_USER_POOL_ID)."
  value       = aws_cognito_user_pool.this.id
}

output "cognito_client_id" {
  description = "SPA app client id, public (backend COGNITO_CLIENT_ID, frontend VITE_COGNITO_CLIENT_ID)."
  value       = aws_cognito_user_pool_client.spa.id
}

output "cognito_authority" {
  description = "OIDC authority (frontend VITE_COGNITO_AUTHORITY)."
  value       = "https://cognito-idp.us-east-1.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "cognito_domain" {
  description = "Managed login base URL (frontend VITE_COGNITO_DOMAIN)."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.us-east-1.amazoncognito.com"
}

output "site_bucket" {
  description = "S3 bucket the frontend uploads its build to (D-31)."
  value       = local.site_bucket
}

output "site_url" {
  description = "Where users open the app: the S3 website endpoint (HTTP, D-31). Allowed in the HTTP API CORS (D-33)."
  value       = local.site_website_url
}

output "site_https_origin" {
  description = "HTTPS origin of the site bucket; serves the Cognito bounce pages under /auth/ (D-31)."
  value       = local.site_https_origin
}

output "api_id" {
  description = "HTTP API id; the cluster stack looks the API up by name and adds its routes (D-33)."
  value       = aws_apigatewayv2_api.this.id
}

output "api_url" {
  description = "HTTPS base URL of the backend api (frontend VITE_API_BASE_URL, D-33). Stable across cluster-down/up."
  value       = aws_apigatewayv2_api.this.api_endpoint
}
