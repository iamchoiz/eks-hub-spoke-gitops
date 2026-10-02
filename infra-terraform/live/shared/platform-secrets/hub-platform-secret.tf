resource "aws_secretsmanager_secret" "hub_platform" {
  name                    = local.hub_platform_secret_name
  description             = var.hub_platform_secret_description
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "hub_platform" {
  secret_id     = aws_secretsmanager_secret.hub_platform.id
  secret_string = local.hub_platform_secret_string

  lifecycle {
    ignore_changes = [secret_string]
  }
}
