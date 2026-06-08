# # tfmodule-aws-config-recorder - input variables (single account, single region).
# #
# # This module provisions ONE AWS Config Recorder + Delivery Channel + IAM Role
# # (+ optional cross-account aggregate authorization) inside whatever account the
# # caller's AWS provider points at. It takes flat, single-stack attributes - there
# # is no `member` object wrapper and no `members` map. The caller (one root stack
# # per account/region) supplies the values via its own tfvars.
# #
# # Format / enum checks live on each variable. Cross-field rules (mutual
# # exclusion of the three recording strategies, recording_frequencies overlap)
# # are enforced as preconditions in main.tf - Terraform 1.5.x does not allow
# # a variable validation to reference other variables.
#

variable "context" {
  description = "Provides standardized naming policy and attribute information for data source reference to define cloud resources for a Project."
  type = object({
    region      = string
    project     = string
    name_prefix = string
    pri_domain  = string
    account_id  = string
    tags        = map(string)
  })
  validation {
    condition     = can(regex("^[0-9]{12}$", var.context.account_id))
    error_message = "context.account_id must be a 12-digit AWS account ID (scopes the S3 delivery prefix AWSLogs/<account_id>/Config/* and the trust-policy aws:SourceAccount condition)."
  }
}

variable "config_role_name" {
  type        = string
  default     = "OrganizationAWSConfigRole"
  description = "Name of the AWS Config service IAM role. Intentionally an organization-standard, unprefixed name so every member account gets the same role name - enabling a single cross-account pattern (arn:aws:iam::*:role/OrganizationAWSConfigRole) in the central bucket/KMS key policies."
}

variable "config_policy_name" {
  type        = string
  default     = "OrganizationAWSConfigDeliveryPolicy"
  description = "Name of the inline IAM policy attached to the Config service role that grants cross-account delivery (s3:PutObject / s3:GetBucketAcl on the central bucket + kms:GenerateDataKey on its CMK). Organization-standard, unprefixed name kept consistent across every member account."
}

variable "all_supported" {
  type        = bool
  default     = true
  description = <<-DESC
    ALL_SUPPORTED_RESOURCE_TYPES strategy. When true, every current and future
    supported type is recorded and resource_types / excluded_resource_types MUST
    be empty (AWS API mutual exclusion). Default true.
  DESC
}

variable "include_global_resource_types" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether to record global resource types (IAM, etc.). Default true. AWS honors
    this ONLY when all_supported = true; in INCLUSION / EXCLUSION mode the module
    forces it to false. For multi-region all_supported accounts, set this false on
    non-home regions to avoid recording the same global resources (and paying) in
    every region.
  DESC
}

variable "resource_types" {
  type        = list(string)
  default     = []
  description = <<-DESC
    INCLUSION_BY_RESOURCE_TYPES strategy. Explicit allow-list of AWS::Service::Type
    identifiers to record. Active only when all_supported = false AND
    excluded_resource_types is empty. Mutually exclusive with excluded_resource_types.
  DESC
  validation {
    condition     = alltrue([for t in var.resource_types : can(regex("^AWS::[A-Za-z0-9]+::[A-Za-z0-9]+$", t))])
    error_message = "Each resource_types entry must match the AWS::Service::Type pattern (e.g. AWS::EC2::Instance)."
  }
}

variable "excluded_resource_types" {
  type        = list(string)
  default     = []
  description = <<-DESC
    EXCLUSION_BY_RESOURCE_TYPES strategy. List of AWS::Service::Type identifiers to
    exclude from recording. When non-empty (and all_supported = false), all other
    supported types - current and future - remain recorded. Mutually exclusive with
    resource_types.
  DESC
  validation {
    condition     = alltrue([for t in var.excluded_resource_types : can(regex("^AWS::[A-Za-z0-9]+::[A-Za-z0-9]+$", t))])
    error_message = "Each excluded_resource_types entry must match the AWS::Service::Type pattern (e.g. AWS::EC2::Instance)."
  }
}

variable "recording_frequency" {
  type        = string
  default     = "DAILY"
  description = "Base capture cadence for every recorded type not individually overridden. DAILY (default, cost-first) | CONTINUOUS."
  validation {
    condition     = contains(["CONTINUOUS", "DAILY"], var.recording_frequency)
    error_message = "recording_frequency must be CONTINUOUS or DAILY."
  }
}

variable "recorder_enabled" {
  type        = bool
  default     = true
  description = "Whether the configuration recorder is started (aws_config_configuration_recorder_status.is_enabled). Set false to pause recording without destroying the recorder/channel."
}

variable "snapshot_delivery_frequency" {
  type        = string
  default     = "Twelve_Hours"
  description = "Delivery Channel snapshot cadence - One_Hour | Three_Hours | Six_Hours | Twelve_Hours (default) | TwentyFour_Hours."
  validation {
    condition     = contains(["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"], var.snapshot_delivery_frequency)
    error_message = "snapshot_delivery_frequency must be One_Hour | Three_Hours | Six_Hours | Twelve_Hours | TwentyFour_Hours."
  }
}

variable "recording_frequencies" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Per-resource-type frequency override map (`AWS::Service::Type` -> "CONTINUOUS"
    | "DAILY"). Layered on top of security_baseline_continuous_types (overrides it
    when the same type appears in both). Keys must NOT overlap with
    excluded_resource_types (excluded types are not recorded - enforced as a
    precondition in main.tf).
  DESC
  validation {
    condition     = alltrue([for t in keys(var.recording_frequencies) : can(regex("^AWS::[A-Za-z0-9]+::[A-Za-z0-9]+$", t))])
    error_message = "Each key in recording_frequencies must match the AWS::Service::Type pattern (e.g. AWS::EC2::Volume)."
  }
  validation {
    condition     = alltrue([for f in values(var.recording_frequencies) : contains(["CONTINUOUS", "DAILY"], f)])
    error_message = "Each value in recording_frequencies must be CONTINUOUS or DAILY."
  }
}

variable "security_baseline_continuous_types" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Curated list of AWS::Service::Type identifiers pinned to CONTINUOUS frequency
    when recording_frequency base = DAILY. Empty list (default) means no
    auto-pinning - the caller supplies the curated set. Must include the 3
    `AWS::Config::*` types that AWS forbids from DAILY mode when base = DAILY.
    Resolution order (later wins): base recording_frequency -> this list ->
    recording_frequencies.
  DESC
  validation {
    condition     = alltrue([for t in var.security_baseline_continuous_types : can(regex("^AWS::[A-Za-z0-9]+::[A-Za-z0-9]+$", t))])
    error_message = "Each security_baseline_continuous_types entry must match the AWS::Service::Type pattern."
  }
}

variable "central_config_bucket" {
  type        = string
  description = "Name of the central Config bucket (OpsnowLog organization-config-s3). Snapshot/History deliveries land in s3://<bucket>/AWSLogs/<account_id>/Config/..."
}

variable "central_config_kms_key_arn" {
  type        = string
  description = "SSE-KMS CMK key ARN (arn:aws:kms:<region>:<account>:key/<id>) for the central Config bucket. Must be a key ARN, NOT an alias ARN - aws_config_delivery_channel.s3_kms_key_arn rejects alias ARNs. The recorder role is granted kms:GenerateDataKey on this key for cross-account delivery."
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.central_config_kms_key_arn))
    error_message = "central_config_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias ARN."
  }
}

variable "enable_aggregate_authorization" {
  type        = bool
  default     = false
  description = "Workload-only true. Issues aws_config_aggregate_authorization so the central Aggregator can read this account's Config data."
}

variable "aggregator_account_id" {
  type        = string
  default     = "276503685119"
  description = "Account ID of the central Aggregator (SGUARD)."
}

variable "aggregator_region" {
  type        = string
  default     = "ap-northeast-2"
  description = "Home region of the central Aggregator. The aggregate-authorization is issued against this (account, region) pair."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Base tag set merged onto every resource (with a per-resource Name added)."
}
