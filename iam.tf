locals {
  # config_role_name이 지정되면 모듈이 커스텀 Config 서비스 역할을 생성한다.
  # 비어 있으면(null 또는 "") 커스텀 역할을 만들지 않고 AWS 서비스 연결 역할
  # (AWSServiceRoleForConfig)을 사용한다.
  create_custom_role = var.config_role_name != null && var.config_role_name != ""

  # 서비스 연결 역할은 커스텀 역할을 만들지 않을 때만 다룬다. 계정에 아직
  # AWSServiceRoleForConfig가 없으면 create_config_service_linked_role = true
  # (기본)로 자동 생성하고, 이미 존재하면 false로 두어 기존 ARN을 그대로 참조한다
  # (aws_iam_service_linked_role는 이미 존재하는 SLR을 다시 만들면 실패하므로).
  create_service_linked_role = !local.create_custom_role && var.create_config_service_linked_role

  service_linked_role_arn = "arn:aws:iam::${var.context.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"

  # 레코더에 전달할 최종 역할 ARN: 커스텀 역할 > 새로 만든 SLR > 기존 SLR(구성).
  config_role_arn = local.create_custom_role ? aws_iam_role.this[0].arn : (
    local.create_service_linked_role ? aws_iam_service_linked_role.config[0].arn : local.service_linked_role_arn
  )

  config_trusted = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "config.amazonaws.com"
        },
        "Action" : "sts:AssumeRole",
        "Condition" : {
          "StringEquals" : {
            "aws:SourceAccount" : [var.context.account_id]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "this" {
  count              = local.create_custom_role ? 1 : 0
  name               = var.config_role_name
  assume_role_policy = local.config_trusted
  tags               = merge(local.tags, { Name = var.config_role_name })
}

resource "aws_iam_role_policy_attachment" "this" {
  count      = local.create_custom_role ? 1 : 0
  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# config_role_name이 비어 있을 때 사용하는 AWS Config 서비스 연결 역할
# (AWSServiceRoleForConfig). 계정에 아직 없을 때만 생성된다.
resource "aws_iam_service_linked_role" "config" {
  count            = local.create_service_linked_role ? 1 : 0
  aws_service_name = "config.amazonaws.com"
  tags             = local.tags
}

# Cross-account delivery policy rendered from templates/config-recorder-iam-policy.tftpl.
# Grants the custom role s3:PutObject / s3:GetBucketAcl on the central bucket. KMS is
# not granted here: delivery encrypts with the central bucket's default SSE-KMS key,
# whose key policy authorizes the config.amazonaws.com service principal directly.
resource "aws_iam_role_policy" "this" {
  count = local.create_custom_role ? 1 : 0
  name  = var.config_policy_name
  role  = aws_iam_role.this[0].id
  policy = templatefile("${path.module}/templates/config-recorder-iam-policy.tftpl", {
    central_config_bucket = var.central_config_bucket
    account_id            = var.context.account_id
  })
}
