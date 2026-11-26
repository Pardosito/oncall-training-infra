# Cognito (INF-031..033, ARCHITECTURE §3): user pool, managed login domain and the SPA's public
# client (authorization code; no secret). Self sign-up on the managed login page with a username,
# email and password; Cognito emails a code to verify the address before the first sign-in (D-35).
# make users (email invite with a temporary password) and make e2e-user still work.
# The e2e user is created by scripts/create-e2e-user.sh, never here (D-22).

resource "aws_cognito_user_pool" "this" {
  name = local.name

  username_configuration {
    case_sensitive = false
  }
  auto_verified_attributes = ["email"]

  # Sign-up sends this code; the account stays UNCONFIRMED until it is entered.
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your On-Call Training verification code"
    email_message        = "Your verification code is {####}."
  }

  # A changed email stays unverified (and the old one keeps working) until the new code is entered.
  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

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

    invite_message_template {
      email_subject = "Your On-Call Training account"
      email_message = "Your username is {username} and your temporary password is {####}. Sign in from the app; you'll pick a new password."
      sms_message   = "On-Call Training: username {username}, temporary password {####}"
    }
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

# Managed login (version 2), styled by aws_cognito_managed_login_branding.spa (D-34).
resource "aws_cognito_user_pool_domain" "this" {
  domain                = "${local.name}-${local.account_id}"
  user_pool_id          = aws_cognito_user_pool.this.id
  managed_login_version = 2
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
