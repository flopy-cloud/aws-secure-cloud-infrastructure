# Bucket donde Config guarda sus registros
# (aws_caller_identity.current ya está definido en cloudtrail.tf)
resource "aws_s3_bucket" "config" {
  bucket        = "secure-infra-config-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "secure-infra-config" }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Rol que usa Config para leer tus recursos y escribir en el bucket
data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  name               = "secure-config-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "config_s3" {
  statement {
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config.arn]
  }
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_iam_role_policy" "config_s3" {
  name   = "config-s3-delivery"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.config_s3.json
}

# El grabador, el canal de entrega y el interruptor
resource "aws_config_configuration_recorder" "main" {
  name     = "secure-infra-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "secure-infra-channel"
  s3_bucket_name = aws_s3_bucket.config.id
  depends_on     = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

# Reglas de cumplimiento
resource "aws_config_config_rule" "ssh_closed" {
  name = "ssh-cerrado-al-mundo"
  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_config_rule" "s3_no_public" {
  name = "s3-sin-lectura-publica"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_config_rule" "rds_no_public" {
  name = "rds-no-publica"
  source {
    owner             = "AWS"
    source_identifier = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}