# Kiro Gateway LXC

## Proxmox guest

| Setting | Value |
|---|---|
| Proxmox node | `kubelab-2` |
| CTID / hostname | `6001` / `kiro-gateway` |
| OS template | Debian 13.6 |
| IPv4 | `192.168.0.17/24`, gateway `192.168.0.1` |
| Bridge / storage | `vmbr0` / `local-lvm` |
| CPU / memory / root disk | 1 vCPU / 1 GiB / 8 GiB |
| Container mode | Unprivileged; nesting disabled; autostart enabled |

`192.168.0.17` did not answer a ping at provisioning time. Add a DHCP exclusion
or reservation for this address to prevent a future collision. Proxmox also
reported that the thin-pool's logical allocation exceeds the VG's free space;
the 8 GiB guest disk is thin-provisioned, so monitor `local-lvm` capacity.

## Installed software and files

- Kiro CLI `3.2.0`, installed as Unix user `kiro` at
  `/home/kiro/.local/bin/kiro-cli`.
- Gateway source at `/opt/kiro-gateway`, copied from the local working tree
  without Git metadata, virtualenv, `.env`, tests, or benchmark-generated nginx
  manifests.
- Python `3.14.10` virtualenv at `/opt/kiro-gateway/.venv`, owned by `kiro`.
- Gateway environment file `/etc/kiro-gateway.env`, mode `0600`, generated
  `KIRO_GATEWAY_API_KEY` stored there. **Do not commit or paste its contents.**
- Systemd unit `kiro-gateway.service` is enabled but not started until Kiro
  authentication is completed.

Gateway settings include `MCP_DISCOVERY=off`, ACP engine `v2`, workspace
`/home/kiro/workspace`, and `ACP_TRUST_TOOLS=true` to preserve built-in tool
execution. Requests authenticated with the gateway key can therefore run Kiro's
file/shell tools as the unprivileged `kiro` user inside the LXC. Do not mount
host secrets or sensitive directories into this container. No MCP servers were
configured.

## Complete Kiro sign-in and start gateway

Authentication was deliberately **not copied** from macOS. Run device flow as
the service user from the Proxmox host:

```bash
ssh kubelab-2
pct exec 6001 -- runuser -u kiro -- env \
  HOME=/home/kiro \
  PATH=/home/kiro/.local/bin:/usr/local/bin:/usr/bin:/bin \
  kiro-cli login --use-device-flow
```

Complete the displayed URL/code flow in your browser. Then start the gateway:

```bash
pct exec 6001 -- systemctl start kiro-gateway
pct exec 6001 -- systemctl status kiro-gateway --no-pager
pct exec 6001 -- curl --fail http://127.0.0.1:8000/health
```

After login, `kiro-cli whoami` should confirm the service user's sign-in. If the
CLI authenticated after gateway startup, restart the service so its ACP process
uses the new sign-in:

```bash
pct exec 6001 -- systemctl restart kiro-gateway
```

From another LAN client, configure OpenAI-compatible clients with base URL
`http://192.168.0.17:8000/v1` and Bearer key from
`/etc/kiro-gateway.env`. Restrict access to the trusted LAN; this endpoint is
plain HTTP and the gateway key is a bearer credential. The authenticated tool
diagnostic is `GET /v1/diagnostics/tools`.

The container's initial `systemctl --failed` showed LXC-related failures for
`dev-mqueue.mount`, `run-lock.mount`, and `tmp.mount`; the gateway unit itself
passes `systemd-analyze verify`. Confirm its runtime status after sign-in.
