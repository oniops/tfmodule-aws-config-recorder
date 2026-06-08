data "aws_iam_policy_document" "config_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    # Confused-deputy guard: only the Config service acting on behalf of THIS
    # account may assume the role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.context.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.config_role_name
  assume_role_policy = data.aws_iam_policy_document.config_trust.json
  tags               = merge(local.tags, { Name = var.config_role_name })
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Cross-account delivery policy rendered from templates/config-recorder-iam-policy.tftpl.
# DeliveryEncrypt grants GenerateDataKey against the bucket-default CMK plus Decrypt
# for retry paths - half of the two-way coupling; the central KMS key policy supplies
# the other half by trusting the org-standard role ARN
# (arn:aws:iam::*:role/${var.config_role_name}).
resource "aws_iam_role_policy" "this" {
  name = var.config_policy_name
  role = aws_iam_role.this.id
  policy = templatefile("${path.module}/templates/config-recorder-iam-policy.tftpl", {
    central_config_bucket      = var.central_config_bucket
    account_id                 = var.context.account_id
    central_config_kms_key_arn = var.central_config_kms_key_arn
  })
}
