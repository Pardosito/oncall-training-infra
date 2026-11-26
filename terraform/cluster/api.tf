# The cluster half of the HTTP API (D-33). The API, its stage, CORS and throttling live in
# foundation so the URL stays the same; everything that points into this VPC lives here and goes
# away with `make cluster-down`. VPC links for HTTP APIs are free; requests cost $1 per million.
# Foundation is found by name, so this stack still takes no Terraform input from it.

data "aws_apigatewayv2_apis" "this" {
  name          = local.name
  protocol_type = "HTTP"

  lifecycle {
    postcondition {
      condition     = length(self.ids) == 1
      error_message = "Expected one HTTP API named oncall-training; run make foundation-apply first (D-33)."
    }
  }
}

data "aws_cognito_user_pools" "this" {
  name = local.name

  lifecycle {
    postcondition {
      condition     = length(self.ids) == 1
      error_message = "Expected one Cognito user pool named oncall-training; run make foundation-apply first."
    }
  }
}

data "aws_cognito_user_pool_clients" "this" {
  user_pool_id = one(data.aws_cognito_user_pools.this.ids)

  lifecycle {
    postcondition {
      condition     = length(self.client_ids) == 1
      error_message = "Expected exactly one app client (the SPA) in the user pool; the JWT authorizer uses it as the audience."
    }
  }
}

locals {
  api_id        = one(data.aws_apigatewayv2_apis.this.ids)
  user_pool_id  = one(data.aws_cognito_user_pools.this.ids)
  spa_client_id = one(data.aws_cognito_user_pool_clients.this.client_ids)
}

resource "aws_security_group" "vpc_link" {
  name        = "${local.name}-vpc-link"
  description = "API Gateway VPC link: out to the internal ALB only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-vpc-link" }
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_to_alb" {
  security_group_id            = aws_security_group.vpc_link.id
  description                  = "HTTP to the internal ALB"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = local.name
  subnet_ids         = [for s in aws_subnet.private : s.id]
  security_group_ids = [aws_security_group.vpc_link.id]
}

# Rejects missing, expired or foreign tokens before they reach the cluster. The backend still
# validates every token itself (defense in depth). For Cognito access tokens, API Gateway checks
# the client_id claim against the audience.
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = local.api_id
  name             = "cognito"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://cognito-idp.${local.region}.amazonaws.com/${local.user_pool_id}"
    audience = [local.spa_client_id]
  }
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id             = local.api_id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.api.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id
  # The ALB's own limit is 60 s; HTTP APIs allow at most 30 s.
  timeout_milliseconds = 30000
}

# No OPTIONS route: with one, API Gateway would send preflights to the backend (which answers 401
# without a token). Without it, API Gateway answers them from the API's CORS configuration.
resource "aws_apigatewayv2_route" "api" {
  api_id             = local.api_id
  route_key          = "ANY /api/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Liveness through the whole chain (API Gateway → VPC link → ALB → pod), no token.
resource "aws_apigatewayv2_route" "healthz" {
  api_id    = local.api_id
  route_key = "GET /healthz"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}
