# SigNoz Host Alerts

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

## Troubleshooting

### Blank plot

Run the exact query in Explorer. Check for:

- `host.name` warning or empty host labels.
- Incorrect `state` filter.
- Wrong metric unit.
- Missing `mountpoint` grouping for filesystem data.
- Query time range before Collector started.

### Filesystem host label missing

Collector must detect and preserve host identity. Example Collector processors:

```yaml
processors:
  resource_detection:
    detectors: [env, system]
    override: true
    system:
      hostname_sources: [os]
  resource/host:
    attributes:
      - key: host.name
        value: <HOST_NAME>
        action: upsert
```

Pipeline order:

```yaml
processors: [resource_detection, resource/host, resource/env]
```

Validate and restart the Collector:

```bash
otelcol-contrib validate --config=/etc/otelcol-contrib/config.yaml
systemctl restart otelcol-contrib
systemctl is-active otelcol-contrib
```

Wait for fresh samples, then verify `host.name` on the exact filesystem query.
