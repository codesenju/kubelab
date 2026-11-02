# SigNoz Alerts

Reference for the SigNoz alert rules and dashboards maintained for this cluster.
Covers host utilization alerts (CPU, memory, filesystem) and the CloudNativePG
(CNPG) backup / WAL-archiving alerts.

> Dashboards are **not** defined as code — they are created and edited directly
> in SigNoz (via UI or the SigNoz MCP server). This file is the source of record
> for their intent, thresholds, and the reasoning behind them, so changes survive
> even though the live objects are not reconciled from Git.

## Table of Contents

- [Host Utilization Alerts](#host-utilization-alerts)
  - [Prerequisites](#prerequisites)
  - [User Workflow](#user-workflow)
    - [CPU utilization](#cpu-utilization)
    - [Memory utilization](#memory-utilization)
    - [Filesystem utilization](#filesystem-utilization)
  - [Agent Workflow](#agent-workflow)
  - [Copy-Paste Agent Prompt](#copy-paste-agent-prompt)
  - [Canonical Alert Properties](#canonical-alert-properties)
  - [Host Utilization Dashboard](#host-utilization-dashboard)
    - [Create From Export](#create-from-export)
  - [Dashboard Agent Prompt](#dashboard-agent-prompt)
- [CNPG Backups & WAL Archiving](#cnpg-backups--wal-archiving)
  - [How WAL archiving differs from backups](#how-wal-archiving-differs-from-backups)
  - [Alert: CNPG WAL archiving stalled](#alert-cnpg-wal-archiving-stalled)
  - [Alert: CNPG WAL archiving failures](#alert-cnpg-wal-archiving-failures)
  - [CNPG Backups & Cluster Health dashboard](#cnpg-backups--cluster-health-dashboard)
  - [S3 region requirement (retention)](#s3-region-requirement-retention)

---

# Host Utilization Alerts

Guide creates CPU, memory, and filesystem alerts for Linux hosts. Replace
`<HOST_NAME>` and `<NOTIFICATION_CHANNEL>` with environment-specific values.

## Prerequisites

- SigNoz MCP server connected, or access to SigNoz UI.
- OpenTelemetry Collector exporting host metrics every 60 seconds.
- A notification channel already exists.
- Resource attribute `host.name` attached to metrics.
- Metrics visible in Explorer before creating alerts.

Verify host metrics in Explorer with:

```text
host.name = '<HOST_NAME>'
```

If filesystem metrics show an empty `host.name`, fix collection labels before
creating a host-scoped alert. Do not remove the host filter; that would alert
on every host.

## User Workflow

Open **Alerts -> Alert Rules -> New Alert** for each alert.

### CPU utilization

Use `system.cpu.time`. This metric has `state` series. Create two queries:

```text
A: system.cpu.time
Filter: host.name = '<HOST_NAME>' AND state IN ('user','system','iowait','irq','softirq','steal','nice')
Time aggregation: Rate
Space aggregation: Sum
Group by: host.name

B: system.cpu.time
Filter: host.name = '<HOST_NAME>'
Time aggregation: Rate
Space aggregation: Sum
Group by: host.name
```

Add formula:

```text
(A / B) * 100
```

Set unit to `Percent`, threshold to `80`, recovery to `70`, and evaluation to
`on average` over `5 minutes`, every `1 minute`. Route threshold notifications
to `<NOTIFICATION_CHANNEL>`.

Do not divide a single CPU state by total CPU time. That produces a state
ratio, not total CPU utilization.

### Memory utilization

Use `system.memory.usage`. Its state values include `used`, `cached`, `free`,
`buffered`, and slab states. Create:

```text
A: system.memory.usage
Filter: host.name = '<HOST_NAME>' AND state = 'used'
Time aggregation: Avg
Space aggregation: Sum
Group by: host.name

B: system.memory.usage
Filter: host.name = '<HOST_NAME>'
Time aggregation: Avg
Space aggregation: Sum
Group by: host.name
```

Add formula:

```text
(A / B) * 100
```

Set unit to `Percent`, threshold to `80`, recovery to `70`, and evaluation to
`on average` over `5 minutes`, every `1 minute`. Route to
`<NOTIFICATION_CHANNEL>`.

This calculates used memory divided by all state-reported memory. It is not
the same as raw `system.memory.usage` in bytes.

### Filesystem utilization

Use `system.filesystem.usage`. Its state values are `used` and `reserved`.
Create:

```text
A: system.filesystem.usage
Filter: host.name = '<HOST_NAME>' AND state = 'used'
Time aggregation: Avg
Space aggregation: Sum
Group by: host.name, mountpoint

B: system.filesystem.usage
Filter: host.name = '<HOST_NAME>'
Time aggregation: Avg
Space aggregation: Sum
Group by: host.name, mountpoint
```

Add formula:

```text
(A / B) * 100
```

Set unit to `Percent`, threshold to `80`, recovery to `70`, and evaluation to
`on average` over `5 minutes`, every `1 minute`. Group notifications by
`mountpoint` and route to `<NOTIFICATION_CHANNEL>`.

The formula matches filesystem utilization shown in host detail views.

## Agent Workflow

An agent creating or modifying these alerts must follow this order:

1. Discover resource keys with `signoz_get_field_keys(signal="metrics", fieldContext="resource")`.
2. Confirm `host.name` is available; use exact host value for scoped alerts or group by it for all-host alerts.
3. Discover metrics with `signoz_list_metrics`.
4. Verify channel name with a fully paginated `signoz_list_notification_channels` call.
5. List all configured rules with `signoz_list_alert_rules`; avoid duplicate names.
6. Probe each metric and exact filter with `signoz_query_metrics`.
7. Dry-run complete formulas with `signoz_execute_builder_query` using absolute timestamps.
8. Update an existing matching rule with `signoz_get_alert` plus `signoz_update_alert`; create only when no matching rule exists.
9. Attach the selected notification channel to every threshold tier. Do not use `preferredChannels` for v2 rules.
10. Re-query each formula after saving and confirm returned series before reporting success.

## Copy-Paste Agent Prompt

Give this prompt to an agent with SigNoz MCP access:

```text
Use SigNoz MCP to create or update three metric alerts: CPU utilization,
memory utilization, and filesystem utilization.

Before doing any SigNoz query or mutation, ask:

"Should these alerts apply to one specific host or to all hosts? If one host,
provide the exact host.name value."

Wait for the answer. For one host, use the exact value in every metric filter.
For all hosts, omit the host.name filter and group results by host.name. Never
guess host scope.

Use an existing notification channel selected by the user. Verify its exact
name with signoz_list_notification_channels. Do not create a replacement
channel. If it does not exist, stop and ask for an existing channel or
permission to create one.

Use these formulas:

1. CPU: system.cpu.time
   A filter: state IN ('user','system','iowait','irq','softirq','steal','nice')
   B filter: no state filter
   Aggregation: rate, then sum across series
   Formula: (A / B) * 100

2. Memory: system.memory.usage
   A filter: state = 'used'
   B filter: no state filter
   Aggregation: avg, then sum across series
   Formula: (A / B) * 100

3. Filesystem: system.filesystem.usage
   A filter: state = 'used'
   B filter: no state filter; this includes used and reserved
   Aggregation: avg, then sum across series
   Group by: mountpoint; also host.name for all-host alerts
   Formula: (A / B) * 100

Verify metric names, host.name, and state values with SigNoz MCP first. If a
host-specific request lacks host.name, stop instead of creating an unscoped
alert.

Configure every alert with:
- Rule type threshold_rule, signal metrics, unit percent
- Critical threshold above 80, recovery target 70
- Match type on_average, rolling evaluation window 5m, frequency 1m
- Notification channel: user-selected channel
- Renotify enabled every 30m while firing
- Filesystem notifications grouped by mountpoint

Use signoz_list_alert_rules to find matching rules. If one exists, fetch it
with signoz_get_alert and preserve unchanged fields while updating it. Otherwise
create a new rule. For v2 rules, put the selected channel in every threshold
tier and never use
preferredChannels.

Disable formula input queries so only the formula is evaluated. Set input query
limits to 10000, formula limit to 100, and non-empty result ordering on every
query. Validate formulas with a real time range before saving.

After each mutation, query the saved formula and confirm it returns series.
Report rule names, IDs, scope, formulas, thresholds, and validation results.
Do not claim success if any alert has no returned data.
```

For formula queries, set component query limits to `10000`, formula limit to
`100`, and use this order on every query:

```json
[{"key":{"name":"__result"},"direction":"desc"}]
```

Use `disabled: true` on formula input queries so only the formula appears as
the alert signal.

## Canonical Alert Properties

All three rules use:

```text
Rule type: threshold_rule
Signal: metrics
Evaluation: rolling, 5m window, 1m frequency
Notification: user-selected channel
Recovery hysteresis: 70% after 80% breach
Host filter: selected host, or none for all-host alerts
```

CPU and memory should normally use warning severity. Use critical only when
operational policy requires paging. Filesystem thresholds should exclude
ephemeral mounts when those mounts create noise.

## Host Utilization Dashboard

Exported dashboard JSON:

```text
Signoz/host-utilization-alerts.json
```

Dashboard ID:

```text
01a0c604-52ef-70d6-ab89-37beab9db267
```

The dashboard contains CPU, memory, and root filesystem percentage panels. All
panels use the `host_name` variable and group results by `host.name`.

### Create From Export

Use the exported file as a SigNoz dashboard import payload. The file contains
the dashboard object itself, not the API response envelope:

```bash
curl -X POST "$SIGNOZ_URL/api/v2/dashboards" \
  -H "Authorization: Bearer $SIGNOZ_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @Signoz/host-utilization-alerts.json
```

Alternatively, open SigNoz **Dashboards**, choose **Import**, and select
`Signoz/host-utilization-alerts.json`.

After import, verify the `Host Name` variable values and set the dashboard time
range to the desired window.

## Dashboard Agent Prompt

Use this prompt when an agent must recreate the dashboard:

```text
Create the SigNoz Host Utilization dashboard from
Signoz/host-utilization-alerts.json.

Import the JSON as a dashboard object, preserving its panels, variables,
layouts, units, thresholds, and Query Builder formulas. Do not recreate panels
with PromQL or replace Query Builder formulas with aggregate queries.

After import, verify:
- Host Name variable exists and uses dynamic metric resource field host.name.
- CPU Utilization shows one series per host.
- Memory Utilization shows one percentage series per host.
- Root Filesystem Utilization shows one `/` percentage series per host.
- Formula input queries are hidden and only formula F1 is displayed.

Open the dashboard in a browser and confirm all three panels render data before
reporting success. Report imported dashboard ID and URL.
```

---

# CNPG Backups & WAL Archiving

Alerts and a dashboard that watch the CloudNativePG clusters and their WAL
archiving / backup health. Clusters archive WAL to an S3-compatible gateway
(RustFS at `s3.iysynergy.com`, region `joburg-north-1`) via the
**barman-cloud plugin** (`barman-cloud.cloudnative-pg.io`, `isWALArchiver: true`),
one `ObjectStore` CR per cluster. The cluster/ObjectStore definitions live in
Git under `addons/*.yaml` and `kustomize/kro-rgd/base/pgcluster.yaml`; the
alerts and dashboard below do not.

Clusters covered: `authentik`, `ekonnecta`, `iysynergy`, `iystudios`,
`drives3`, `n8n`.

## How WAL archiving differs from backups

These are two independent things, and the alerts are designed around the
difference:

- **Base backup** — a full snapshot, taken once a day via `scheduledBackup`
  (cron `0 0 2 * * *`).
- **WAL archiving** — continuous shipping of each write-ahead-log segment to
  object storage *between* backups. Point-in-time recovery (PITR) =
  last base backup **+** the WAL stream since then.

Key gotcha observed in this environment: most of these clusters are **low- or
zero-write** (checkpoints writing 0 buffers). On a truly idle PostgreSQL,
`archive_timeout` (set to 1800s / 30m) does **not** force a segment, because
there is no WAL activity to flush. So an idle cluster legitimately archives
only once per day — when the scheduled base backup forces a WAL switch. A
"seconds since last archive" value approaching ~24h is therefore **normal** for
an idle cluster, not a failure. `authentik` is the one high-traffic cluster and
archives every few minutes.

## Alert: CNPG WAL archiving stalled

- **Rule ID:** `01a19489-4493-725a-b3d1-6cb9b549b07d`
- **Severity:** critical · **Labels:** `severity=critical`, `team=platform`
- **Signal / metric:** metrics, `cnpg_pg_stat_archiver_seconds_since_last_archival`
- **Aggregation:** time `avg`, space `max`; group by `cnpg_cluster`, `k8s_namespace_name`
- **Threshold:** `above 90000` seconds (**25h**), match `at_least_once`, unit `s`
- **Evaluation:** rolling, 5m window, 1m frequency
- **Notification:** channel `n8n`; renotify every 4h while firing; grouped by
  `cnpg_cluster`, `k8s_namespace_name`

**Why 25h and not 3h (the original value):** because idle clusters legitimately
sit near 24h between archives (see section above), a 3h threshold false-fired
continuously on every idle cluster. 25h sits just above the once-daily backup
cadence, so it stops crying wolf but still catches a genuinely dead archive
path — i.e. even the daily backup's forced WAL archive did not happen. Do **not**
lower this to "match the backup interval"; that would re-introduce the false
alarms. If you want a faster signal, rely on the failures alert below instead,
which is cadence-independent.

> Changed 2026-11-01: threshold raised 10800 → 90000 s; description/annotation
> updated from ">3h" to ">25h".

## Alert: CNPG WAL archiving failures

- **Rule ID:** `01a19489-7507-7107-8c36-fbbb8200fae6`
- **Severity:** warning · **Labels:** `severity=warning`, `team=platform`
- **Signal / metric:** metrics, `cnpg_pg_stat_archiver_failed_count`
  (`increase` over the window), group by `cnpg_cluster`
- **Intent:** fires within minutes when a cluster records an *actively failing*
  WAL archive attempt, independent of WAL cadence. This is the fast safety net
  that the "stalled" alert's 25h threshold intentionally trades away. A common
  cause is a stale S3 (RustFS) secret key producing `SignatureDoesNotMatch`.

Leave this rule alone when tuning the "stalled" threshold — the two are
complementary: *failures* catches active errors fast, *stalled* catches a
silently dead archive path on an otherwise error-free cluster.

## CNPG Backups & Cluster Health dashboard

- **Name:** `CNPG Backups & Cluster Health`
- **Dashboard ID:** `01a19480-1e77-7851-9972-138643289f58`
- **Variable:** `$cnpg_cluster` (dynamic, metric resource field `cnpg_cluster`,
  multi-select, all-value)

Panels:

| Panel ID | Title | Metric | Threshold line |
|---|---|---|---|
| `wal-staleness` | Seconds since last successful WAL archive | `cnpg_pg_stat_archiver_seconds_since_last_archival` (max) | **90000 s ("25h stall")** |
| `archive-failures` | WAL archive failures (increase 10m) | `cnpg_pg_stat_archiver_failed_count` (increase) | 1 ("failures") |
| `cluster-up` | PostgreSQL up (1=up) | `cnpg_collector_up` (min) | 1 ("down") |
| `wal-backlog` | WAL segments waiting to archive (ready) | `cnpg_collector_pg_wal_archive_status` filtered `value='ready'` | 10 ("backlog") |
| `replication-lag` | Replication lag behind primary | `cnpg_pg_replication_lag` (max), unit `s` | 30 ("30s") |

> Changed 2026-11-01: `wal-staleness` threshold raised 10800 → 90000 s; label
> "3h stall" → "25h stall". Kept in sync with the "stalled" alert above.

To edit a single panel threshold without rebuilding the dashboard, use the
SigNoz MCP `signoz_patch_dashboard` with an RFC-6902 patch, e.g.:

```json
[
  {"op":"replace","path":"/spec/panels/wal-staleness/spec/plugin/spec/thresholds/0/value","value":90000},
  {"op":"replace","path":"/spec/panels/wal-staleness/spec/plugin/spec/thresholds/0/label","value":"25h stall"}
]
```

## S3 region requirement (retention)

The barman-cloud **retention** path (`barman-cloud-backup-delete`, which calls
`ListObjectsV2`) requires an S3 **region** to be configured. Against the RustFS
gateway, omitting it causes a recurring, non-fatal error every 5 minutes:

```text
Barman cloud backup delete exception: An error occurred (InvalidArgument)
when calling the ListObjectsV2 operation: Invalid argument
```

WAL upload and base backups still succeed without a region — only retention
(old-backup pruning) fails, so the bucket grows unbounded. Fix: every
`s3-creds` secret must carry `REGION: "joburg-north-1"`, and each `ObjectStore`
must reference it under `spec.configuration.s3Credentials.region`
(`{key: REGION, name: s3-creds}`). This is wired into
`kustomize/kro-rgd/base/pgcluster.yaml` (so all current and future clusters get
it) and the `s3-creds` secrets in `addons/*.yaml`.
