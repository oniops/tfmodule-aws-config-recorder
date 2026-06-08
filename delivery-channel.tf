resource "aws_config_delivery_channel" "this" {
  name           = "${local.name_prefix}-config-recorder-channel"
  s3_bucket_name = var.central_config_bucket

  # Explicit SSE-KMS for delivered objects. Pairs with the kms:GenerateDataKey
  # grant on the recorder role (iam.tf); without this the channel relies only on
  # the bucket's default encryption, which can drift from the granted CMK.
  s3_kms_key_arn = var.central_config_kms_key_arn

  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_delivery_frequency
  }

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_iam_role_policy.this,
  ]

}
