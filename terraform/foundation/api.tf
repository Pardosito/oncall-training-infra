# Public HTTPS entry for the backend api (D-33): an API Gateway HTTP API with a URL that survives
# cluster-down/up. It costs per request only, so it stays in foundation. The cluster stack adds
# what depends on the cluster (VPC link, integration, routes, JWT authorizer); while the cluster
# is down the API has no routes and answers 404.

resource "aws_apigatewayv2_api" "this" {
  name          = local.name
  protocol_type = "HTTP"
  description   = "Backend api for the SPA (D-33). Routes come from the cluster stack."

  # API Gateway answers the preflight and ignores CORS headers from the backend, so CORS lives
  # here only (backend CORS_ORIGINS stays unset). localhost is the Vite dev server.
  cors_configuration {
    allow_origins  = [local.site_website_url, "http://localhost:5173"]
    allow_methods  = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers  = ["authorization", "content-type", "x-request-id"]
    expose_headers = ["x-request-id"]
    max_age        = 600
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = 7
  tags              = local.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  # Applies to every route; the dashboard polls about once a second per user.
  default_route_settings {
    throttling_rate_limit  = var.api_throttle_rate
    throttling_burst_limit = var.api_throttle_burst
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId"
      time      = "$context.requestTime"
      ip        = "$context.identity.sourceIp"
      method    = "$context.httpMethod"
      path      = "$context.path"
      status    = "$context.status"
      latencyMs = "$context.responseLatency"
      authError = "$context.authorizer.error"
      integErr  = "$context.integrationErrorMessage"
    })
  }

  tags = local.tags
}
