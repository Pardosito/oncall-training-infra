# Managed login (version 2) styled as Carbon's g100 theme so sign-in matches the SPA (D-34).
# branding/carbon-g100.json is Cognito's full default settings document with Carbon colors,
# square corners and the dark scheme applied by branding/carbon-g100.jq. To regenerate it, create
# a throwaway branding with --use-cognito-provided-values, describe it with
# --return-merged-resources, pipe .ManagedLoginBranding.Settings through the jq file, then delete
# the throwaway branding. Fonts and layout stay Cognito's; only colors, radii and assets change.

resource "aws_cognito_managed_login_branding" "spa" {
  user_pool_id = aws_cognito_user_pool.this.id
  client_id    = aws_cognito_user_pool_client.spa.id

  settings = jsonencode(jsondecode(file("${path.module}/branding/carbon-g100.json")))

  asset {
    category   = "FORM_LOGO"
    color_mode = "DARK"
    extension  = "SVG"
    bytes      = filebase64("${path.module}/branding/logo.svg")
  }

  asset {
    category   = "FAVICON_SVG"
    color_mode = "DYNAMIC"
    extension  = "SVG"
    bytes      = filebase64("${path.module}/branding/logo.svg")
  }
}
