# OpenCode with Kiro authentication

This guide reproduces an OpenCode setup that uses Kiro as a model provider.
It contains no credentials, tokens, private endpoints, account names, or
machine-specific paths.

## Requirements

- OpenCode 2 stable
- Node.js 20 or newer
- `kiro-cli` installed and available on `PATH`
- An eligible Kiro subscription or AWS Builder ID account

Check the installed tools before continuing:

```bash
opencode --version
node --version
kiro-cli --version
```

## Install the Kiro plugin

Add the pinned plugin to the global OpenCode configuration at
`~/.config/opencode/opencode.json`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    "opencode-kiro@0.5.2"
  ]
}
```

Pin the exact plugin version for reproducible installations. Do not copy an
existing user's OpenCode database, Kiro credential files, browser profile, or
environment variables to another machine.

## Authenticate

Authenticate Kiro locally. Kiro CLI owns credential storage and refresh:

```bash
kiro-cli login
opencode auth login
```

In the OpenCode authentication flow:

1. Select **Kiro**.
2. Select **Kiro CLI Login**.
3. Complete browser authentication when prompted.

If OpenCode authentication times out, run `kiro-cli login` first, then repeat
`opencode auth login`.

## Verify model discovery

List models after authentication:

```bash
opencode models
```

The plugin discovers the available Kiro models dynamically. Use an exact model
ID returned by that command:

```bash
opencode run -m kiro/<exact-model-id> "hello"
```

Model listing alone does not prove that authentication works; make one small
real request and confirm it succeeds.

## Optional plugin settings

The plugin works with defaults. If customization is required, use the object
form and keep values non-secret:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    {
      "package": "opencode-kiro@0.5.2",
      "options": {
        "agent": "opencode",
        "mcpTimeout": 45,
        "discover": true,
        "stall": {
          "afterMs": 10000,
          "live": "reasoning"
        }
      }
    }
  ]
}
```

Do not put API keys, OAuth tokens, cookies, client secrets, or credential file
contents in this configuration.

## Optional OpenCode integrations

Additional integrations are independent of Kiro authentication:

- OpenTelemetry plugin: add the approved, pinned package only when telemetry
  is required.
- Hindsight memory: install and configure Hindsight separately, then add its
  plugin using the path or package documented for that installation.
- Other OpenCode plugins and skills can be added without changing the Kiro
  authentication flow.

Keep local absolute paths out of shared repository configuration. Prefer a
documented package name or a machine-local configuration file.

## Troubleshooting

### Kiro is missing from `opencode models`

Run `opencode auth login` and complete the Kiro CLI Login flow. If the list is
still empty, inspect OpenCode server logs for `opencode-kiro` discovery errors.

### Authentication times out

Run:

```bash
kiro-cli login
opencode auth login
```

Complete the browser flow before the timeout expires.

### Provider appears but requests fail

Confirm that `kiro-cli` is on the `PATH` inherited by OpenCode, authenticate
again, and retry with an exact model ID from `opencode models`.

### OpenCode or plugin compatibility problems

`opencode-kiro@0.5.2` targets OpenCode 2 stable and was tested against the
OpenCode 2.0.x line. Check the plugin compatibility table before upgrading
OpenCode or the plugin together.

## Security checklist

- Authenticate separately on every machine.
- Never commit credential files, tokens, cookies, or browser state.
- Keep secrets in the operating system credential store or approved secret
  manager.
- Use pinned plugin versions in shared configuration.
- Treat OpenCode as a privileged local agent: it can read files and execute
  tools with the server account's permissions.

## References

- [OpenCode providers](https://opencode.ai/docs/providers)
- [OpenCode configuration](https://opencode.ai/docs/config)
- [`opencode-kiro` documentation](https://www.npmjs.com/package/opencode-kiro)
- [Kiro CLI documentation](https://kiro.dev/docs/cli/)
