data "aws_region" "current" {}

resource "aws_securityhub_account" "main" {
  enable_default_standards = false # activamos solo el estándar que elegimos abajo

  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]
}