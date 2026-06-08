output "recorder_name" {
  description = "Name of the AWS Config Configuration Recorder."
  value       = aws_config_configuration_recorder.this.name
}

output "delivery_channel_name" {
  description = "Name of the AWS Config Delivery Channel."
  value       = aws_config_delivery_channel.this.name
}

output "iam_role_arn" {
  description = "ARN of the AWS Config service role created in this account."
  value       = aws_iam_role.this.arn
}

output "aggregate_authorization_arn" {
  description = "Cross-account aggregation authorization ARN. Null when enable_aggregate_authorization = false (intentionally excluded from the central Aggregator surface)."
  value       = one(aws_config_aggregate_authorization.to_aggregator[*].arn)
}
