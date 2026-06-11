resource "aws_config_delivery_channel" "this" {
  name           = "${local.name_prefix}-config-recorder-channel"
  s3_bucket_name = var.central_config_bucket

  # No s3_kms_key_arn: delivered objects inherit the central bucket's default
  # SSE-KMS encryption. AWS Config delivers as the service principal
  # config.amazonaws.com, which the central bucket/KMS key policies authorize
  # (scoped by aws:SourceAccount), so the module grants no per-key IAM permission.

  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_delivery_frequency
  }

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_iam_role_policy.this,
  ]

}
