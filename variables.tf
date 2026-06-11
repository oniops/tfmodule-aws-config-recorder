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
  default     = null # "OrganizationAWSConfigRole"
  description = "Name of the AWS Config service IAM role. Intentionally an organization-standard, unprefixed name so every member account gets the same role name - enabling a single cross-account pattern (arn:aws:iam::*:role/OrganizationAWSConfigRole) in the central bucket/KMS key policies. Leave null/empty to skip creating a custom role and use the AWS service-linked role AWSServiceRoleForConfig instead (see create_config_service_linked_role)."
}

variable "create_config_service_linked_role" {
  type        = bool
  default     = true
  description = <<-DESC
    Only relevant when config_role_name is null/empty (no custom role). When true
    (default), the module creates the AWS Config service-linked role
    AWSServiceRoleForConfig and points the recorder at it. Set false when the
    account already has this service-linked role - the module then references its
    ARN without trying to recreate it (aws_iam_service_linked_role fails on an
    already-existing SLR). Ignored when config_role_name is set.
  DESC
}

variable "config_policy_name" {
  type        = string
  default     = "OrganizationAWSConfigDeliveryPolicy"
  description = "Name of the inline IAM policy attached to the Config service role that grants cross-account delivery (s3:PutObject / s3:GetBucketAcl on the central bucket). Organization-standard, unprefixed name kept consistent across every member account. Only created when a custom role is used (config_role_name set)."
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
    List of AWS::Service::Type identifiers pinned to CONTINUOUS frequency when
    recording_frequency base = DAILY. Each entry is pinned ONLY if the active
    strategy actually records it (an entry outside an INCLUSION allow-list, or
    inside an EXCLUSION deny-list, is harmlessly skipped).

    Do NOT list the AWS::Config::* internal compliance types here
    (ConfigurationRecorder, ConformancePackCompliance, ResourceCompliance): AWS
    records them continuously by default and rejects them in any recording group
    or recording-mode override, so the module neither pins nor emits them (a
    precondition rejects them with a clear message).

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
