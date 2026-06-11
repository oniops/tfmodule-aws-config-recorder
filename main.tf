
locals {
  name_prefix = var.context.name_prefix

  # Single tag source: context.tags (org-standard policy) overlaid by var.tags
  # (module-level overrides). Merged onto every taggable resource.
  tags = merge(var.context.tags, var.tags)

  use_exclusion = length(var.excluded_resource_types) > 0

  use_inclusion = !var.all_supported && !local.use_exclusion && length(var.resource_types) > 0

  # AWS::Config::* internal compliance types are SYSTEM resource types: AWS records
  # them continuously by default and REJECTS any attempt to list them in a recording
  # group or recording-mode override ("Failed to add ... this is a system resource
  # type of AWS Config. The recording of this type is enabled by default."). They
  # must never be emitted - not included, not excluded, not pinned, not overridden.
  system_recorded_types = [
    "AWS::Config::ConfigurationRecorder",
    "AWS::Config::ConformancePackCompliance",
    "AWS::Config::ResourceCompliance",
  ]

  # Caller-curated CONTINUOUS baseline. System types are dropped defensively (the
  # precondition below already rejects them with a clear message). Each remaining
  # type is pinned ONLY when the active strategy actually records it, so a baseline
  # entry outside an INCLUSION allow-list (or inside an EXCLUSION deny-list) is
  # harmlessly skipped rather than producing an override for a non-recorded type.
  baseline_continuous_candidates = distinct([
    for t in var.security_baseline_continuous_types : t
    if !contains(local.system_recorded_types, t)
  ])

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
    if !contains(var.excluded_resource_types, t) && !contains(local.system_recorded_types, t)
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
}

resource "aws_config_configuration_recorder" "this" {
  name     = local.recorder_name
  role_arn = local.config_role_arn

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
    # System resource types: AWS records the AWS::Config::* internal compliance types
    # continuously by default and rejects them in any recording group or recording-mode
    # override. They must not appear in any caller input.
    precondition {
      condition = length(setintersection(
        toset(local.system_recorded_types),
        toset(concat(
          var.resource_types,
          var.excluded_resource_types,
          keys(var.recording_frequencies),
          var.security_baseline_continuous_types,
        )),
      )) == 0
      error_message = "AWS::Config::ConfigurationRecorder / ConformancePackCompliance / ResourceCompliance are system resource types that AWS records continuously by default and forbids in any recording group or recording-mode override. Remove them from resource_types, excluded_resource_types, recording_frequencies, and security_baseline_continuous_types."
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
