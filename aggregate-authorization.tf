# Cross-account aggregation authorization (account_aggregation_source mode).
#
# Grants the central Aggregator (SGUARD) permission to read this account's Config
# data. The delegated-admin aggregator (account mode) couples bidirectionally
# with this resource - without the authorization the aggregator hits
# default-deny on every read.
#
# Issuance policy: workload accounts only (enable_aggregate_authorization = true).
# Non-workload accounts (MST / SGUARD / OpsnowLog) leave this false to stay off
# the aggregator surface.
#
# Ordering: apply this account first (issue authorization) then delegated-admin
# (register account_ids). Reversed ordering produces a transient finding gap
# until AWS eventual consistency catches up.

resource "aws_config_aggregate_authorization" "to_aggregator" {
  count                 = var.enable_aggregate_authorization ? 1 : 0
  account_id            = var.aggregator_account_id
  authorized_aws_region = var.aggregator_region
  tags                  = merge(local.tags, { Name = "${local.name_prefix}-config-aggregate-authorization" })
}
