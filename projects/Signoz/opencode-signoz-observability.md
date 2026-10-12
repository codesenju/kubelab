# OpenCode Observability in SigNoz

This guide configures OpenCode to export traces, metrics, and log events to a
SigNoz OpenTelemetry Collector.

## Prerequisites

- OpenCode installed and working.
- Access to the OpenCode configuration directory.
- SigNoz OTLP collector endpoint reachable from the machine running OpenCode.
- Collector ingress configured for OTLP HTTP/protobuf at `/v1/traces`,
  `/v1/metrics`, and `/v1/logs`.
- Authentication headers, if collector requires them.

## Install Plugin

The plugin is published as `@devtheops/opencode-plugin-otel`.

Verify the package is available:

```sh
npm view @devtheops/opencode-plugin-otel version
```

Add it to `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@devtheops/opencode-plugin-otel"]
}
```

Preserve existing OpenCode `mcp`, `provider`, and `model` settings when adding
the plugin.

## Configure OTLP Export

Set variables in the same shell that launches OpenCode:

```sh
export OPENCODE_ENABLE_TELEMETRY=1
export OPENCODE_OTLP_ENDPOINT="https://<signoz-collector-host>"
export OPENCODE_OTLP_PROTOCOL="http/protobuf"
```

For example:

```sh
export OPENCODE_ENABLE_TELEMETRY=1
export OPENCODE_OTLP_ENDPOINT="https://signoz-otel-collector.example.com"
export OPENCODE_OTLP_PROTOCOL="http/protobuf"
opencode
```

With `http/protobuf`, the plugin appends signal paths automatically. Use the
collector base URL, not `/v1/traces`:

```text
<endpoint>/v1/traces
<endpoint>/v1/metrics
<endpoint>/v1/logs
```

Do not use the default `grpc` protocol unless the endpoint exposes OTLP gRPC.

If collector authentication is required, provide headers without committing
secrets:

```sh
export OPENCODE_OTLP_HEADERS="Authorization=Bearer <token>"
```

For multiple headers, use comma-separated `key=value` pairs:

```sh
export OPENCODE_OTLP_HEADERS="x-api-key=<key>,x-tenant-id=<tenant>"
```

Optional resource and span attributes:

```sh
export OPENCODE_RESOURCE_ATTRIBUTES="deployment.environment=local"
export OPENCODE_SPAN_ATTRIBUTES="team=platform"
```

Do not set `OPENCODE_DISABLE_TRACES`. The plugin exports traces by default.

## Persist Environment Variables

Add exports to `~/.zshrc` for zsh users:

```sh
export OPENCODE_ENABLE_TELEMETRY=1
export OPENCODE_OTLP_ENDPOINT="https://<signoz-collector-host>"
export OPENCODE_OTLP_PROTOCOL="http/protobuf"
```

Reload the shell:

```sh
source ~/.zshrc
```

Check resolved values before launching OpenCode:

```sh
env | grep '^OPENCODE_'
```

Never print or commit values containing authentication tokens.

## Verify Collector Reachability

Check DNS and TLS connectivity:

```sh
curl -vkI --connect-timeout 5 \
  "https://<signoz-collector-host>"
```

A `404` response at the collector root does not necessarily indicate failure;
OTLP routes are signal-specific. Validate that reverse proxy or ingress routes
POST requests to `/v1/traces`, `/v1/metrics`, and `/v1/logs`.

## Verify OpenCode Export

Launch OpenCode with debug output:

```sh
OPENCODE_LOG_LEVEL=debug opencode 2>&1 | tee /tmp/opencode-otel.log
```

Create a new session, then search exporter messages:

```sh
grep -Ei 'otel|otlp|trace|export|401|404|unimplemented|error' \
  /tmp/opencode-otel.log
```

Interpret common failures:

| Output | Likely cause |
| --- | --- |
| `404` | Collector ingress does not route `/v1/traces` or another OTLP path. |
| `401` or `403` | Missing or invalid `OPENCODE_OTLP_HEADERS`. |
| `UNIMPLEMENTED` | Protocol or collector receiver mismatch. |
| No plugin or OTLP output | Plugin not loaded, or OpenCode was launched before environment variables were set. |
| TLS or connection error | DNS, certificate, firewall, or endpoint availability problem. |

Do not include the shell prompt when copying commands. Run only the command
after the prompt, for example:

```sh
OPENCODE_LOG_LEVEL=debug opencode
```

## Verify in SigNoz

Open **Traces** in SigNoz and query recent data. Search for the OpenCode
service/resource attributes emitted by the plugin. A new OpenCode session must
be created after changing configuration.

Using SigNoz MCP, check signal availability and recent trace count with the
organization overview. Successful export should show:

- Trace count greater than zero.
- A recent trace observation time.
- Trace spans visible in the Traces explorer.

Metrics and logs can continue flowing even when traces fail, so verify each
signal independently.

## Troubleshooting Checklist

1. Confirm plugin appears in `~/.config/opencode/opencode.json`.
2. Confirm package availability with `npm view`.
3. Confirm variables exist in the process environment that launches OpenCode.
4. Confirm `OPENCODE_OTLP_PROTOCOL=http/protobuf` for HTTPS HTTP ingress.
5. Confirm endpoint is the collector base URL without `/v1/traces`.
6. Confirm ingress routes all three OTLP HTTP paths.
7. Confirm authentication headers and certificate trust.
8. Confirm `OPENCODE_DISABLE_TRACES` is unset.
9. Restart OpenCode and create a fresh session.
10. Check OpenCode debug output and collector logs together.

## References

- [SigNoz OpenCode observability](https://signoz.io/docs/opencode-observability/)
- [OpenCode OTEL plugin](https://www.npmjs.com/package/@devtheops/opencode-plugin-otel)
- [OpenCode configuration schema](https://opencode.ai/config.json)
