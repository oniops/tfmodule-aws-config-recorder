
locals {
  name_prefix = var.context.name_prefix

  # Single tag source: context.tags (org-standard policy) overlaid by var.tags
  # (module-level overrides). Merged onto every taggable resource.
  tags = merge(var.context.tags, var.tags)

  use_exclusion = length(var.excluded_resource_types) > 0

  use_inclusion = !var.all_supported && !local.use_exclusion && length(var.resource_types) > 0

  # Candidate types to pin to CONTINUOUS under a DAILY base: the AWS-mandated
  # AWS::Config::* types plus the caller's curated baseline. Each is pinned ONLY
  # when the active strategy actually records it, so a baseline entry outside an
  # INCLUSION allow-list (or inside an EXCLUSION deny-list) is harmlessly skipped
  # rather than producing an override for a non-recorded type.
  baseline_continuous_candidates = distinct(concat(
    local.daily_unsupported_types,
    var.security_baseline_continuous_types,
  ))

  baseline_overrides = var.recording_frequency == "DAILY" ? {
    for t in local.baseline_continuous_candidates : t => "CONTINUOUS"
    if(
      var.all_supported
      || (local.use_inclusion && contains(var.resource_types, t))
      || (local.use_exclusion && !contains(var.excluded_resource_types, t))
    )
  } : {}

  effective_frequencies = {
    for t, f in merge(local.baseline_overrides, var.recording_frequencies) :
    t => f
    if !contains(var.excluded_resource_types, t)
  }

  override_frequencies = distinct([
    for f in values(local.effective_frequencies) : f
    if f != var.recording_frequency
  ])

  recording_mode_overrides = [
    for freq in local.override_frequencies : {
      description         = "${freq} cadence - security baseline pin + per-type overrides"
      resource_types      = sort([for t, f in local.effective_frequencies : t if f == freq])
      recording_frequency = freq
    }
  ]

  recorder_name = "${local.name_prefix}-config-recorder"

  # AWS::Config::* internal compliance types that AWS forbids from DAILY
  # recording (must be CONTINUOUS). See config-recorder-supported-resource-types.md.
  daily_unsupported_types = [
    "AWS::Config::ConfigurationRecorder",
    "AWS::Config::ConformancePackCompliance",
    "AWS::Config::ResourceCompliance",
  ]

  # Subset of the forbidden types that this recorder actually records, given the
  # active strategy. ALL_SUPPORTED records everything; INCLUSION only the
  # allow-list; EXCLUSION everything except the deny-list.
  recorded_daily_unsupported = [
    for t in local.daily_unsupported_types : t
    if(
      var.all_supported
      || (local.use_inclusion && contains(var.resource_types, t))
      || (local.use_exclusion && !contains(var.excluded_resource_types, t))
    )
  ]
}

resource "aws_config_configuration_recorder" "this" {
  name     = local.recorder_name
  role_arn = aws_iam_role.this.arn

  recording_group {
    all_supported = var.all_supported

    # AWS API constraint: include_global_resource_types is honored ONLY when
    # all_supported = true. Force false in INCLUSION / EXCLUSION mode, otherwise
    # the recorder is rejected.
    include_global_resource_types = var.all_supported ? var.include_global_resource_types : false

    # INCLUSION strategy - explicit allow-list. Null (unset) in ALL_SUPPORTED or
    # EXCLUSION mode so the strategies stay mutually exclusive.
    resource_types = local.use_inclusion ? var.resource_types : null

    dynamic "exclusion_by_resource_types" {
      for_each = local.use_exclusion ? [1] : []
      content {
        resource_types = var.excluded_resource_types
      }
    }

    dynamic "recording_strategy" {
      for_each = (local.use_exclusion || local.use_inclusion) ? [1] : []
      content {
        use_only = local.use_exclusion ? "EXCLUSION_BY_RESOURCE_TYPES" : "INCLUSION_BY_RESOURCE_TYPES"
      }
    }
  }

  recording_mode {
    recording_frequency = var.recording_frequency

    dynamic "recording_mode_override" {
      for_each = local.recording_mode_overrides
      content {
        description         = recording_mode_override.value.description
        resource_types      = recording_mode_override.value.resource_types
        recording_frequency = recording_mode_override.value.recording_frequency
      }
    }
  }

  # Cross-field rules (Terraform 1.5.x cannot reference other variables inside a
  # variable validation block, so they are enforced here at plan time).
  lifecycle {
    precondition {
      condition     = !(var.all_supported && (length(var.resource_types) > 0 || length(var.excluded_resource_types) > 0))
      error_message = "all_supported = true cannot be combined with resource_types or excluded_resource_types (ALL_SUPPORTED records every supported type)."
    }
    precondition {
      condition     = !(length(var.resource_types) > 0 && length(var.excluded_resource_types) > 0)
      error_message = "resource_types (INCLUSION) and excluded_resource_types (EXCLUSION) are mutually exclusive - set at most one."
    }
    precondition {
      condition     = length(setintersection(toset(var.excluded_resource_types), toset(keys(var.recording_frequencies)))) == 0
      error_message = "Keys of recording_frequencies must not overlap with excluded_resource_types - excluded types are not recorded."
    }
    # INCLUSION mode: every type that gets a recording_mode_override (from
    # recording_frequencies or security_baseline_continuous_types) must also be in
    # the allow-list. AWS Config rejects a recording-mode override for a type the
    # recorder does not record.
    precondition {
      condition     = !local.use_inclusion || length(setsubtract(toset(keys(local.effective_frequencies)), toset(var.resource_types))) == 0
      error_message = "In INCLUSION mode, all recording_frequencies keys and security_baseline_continuous_types must also appear in resource_types - a recording-mode override cannot target a non-recorded type."
    }
    # DAILY base: the AWS::Config::* internal compliance types that AWS forbids from
    # DAILY recording must be pinned to CONTINUOUS (via security_baseline_continuous_types
    # or recording_frequencies) for every such type this recorder actually records.
    precondition {
      condition     = var.recording_frequency != "DAILY" || alltrue([for t in local.recorded_daily_unsupported : lookup(local.effective_frequencies, t, "DAILY") == "CONTINUOUS"])
      error_message = "When recording_frequency = DAILY, the AWS::Config::* types AWS forbids from DAILY recording (ConfigurationRecorder, ConformancePackCompliance, ResourceCompliance) must be pinned to CONTINUOUS via security_baseline_continuous_types or recording_frequencies."
    }
  }
}

# Activates the recorder. The Delivery Channel must exist first - AWS Config
# rejects enabling a recorder that has no channel.

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = var.recorder_enabled

  depends_on = [aws_config_delivery_channel.this]
}
