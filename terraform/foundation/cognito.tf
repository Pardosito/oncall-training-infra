# Cognito (INF-031..033, ARCHITECTURE §3): user pool, managed login domain and the SPA's public
# client (authorization code; no secret). Users sign up themselves on the managed login page.
# The e2e user is created by scripts/create-e2e-user.sh, never here (D-22).

resource "aws_cognito_user_pool" "this" {
  name = local.name

  username_configuration {
    case_sensitive = false
  }
  auto_verified_attributes = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
    string_attribute_constraints {
      min_length = 3
      max_length = 254
    }
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  deletion_protection = "INACTIVE"
  tags                = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Classic hosted UI (version 1): version 2 needs a branding resource before the page renders.
resource "aws_cognito_user_pool_domain" "this" {
  domain                = "${local.name}-${local.account_id}"
  user_pool_id          = aws_cognito_user_pool.this.id
  managed_login_version = 1
}

resource "aws_cognito_user_pool_client" "spa" {
  name         = "${local.name}-spa"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  # HTTPS bounce pages on the site bucket (site.tf, D-31) + the Vite dev server.
  callback_urls = [
    "${local.site_https_origin}/auth/callback.html",
    "http://localhost:5173/callback",
  ]
  logout_urls = [
    "${local.site_https_origin}/auth/signed-out.html",
    "http://localhost:5173/",
  ]

  # SRP for the managed login page; USER_PASSWORD for the e2e user script.
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 1
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
