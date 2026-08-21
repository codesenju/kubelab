# Transmission Hybrid VPN Guide

## Summary

Transmission runs two network layers:

```text
Transmission LXC (192.*.*.*)
  -> WireGuard full-tunnel (10.*.*.*)
  -> Tailscale transport (100.*.*.* -> 100.*.*.*)
  -> kubelab-cloud WireGuard server
  -> Internet
```

WireGuard carries Transmission's internet traffic. Tailscale transports WireGuard packets and keeps the home-to-cloud path reachable without inbound home ports. Tailscale must remain online while WireGuard is active.

Expected public IP from Transmission: cloud/VPS egress address.

## Beginner Setup

This guide assumes:

- A VPS running the WireGuard server.
- Headscale/Tailscale connectivity between home Transmission and VPS.
- Transmission running directly on a Linux host or LXC.
- Root access on both systems.

Use placeholders below. Never paste private keys, preshared keys, auth keys, or real infrastructure addresses into documentation.

### 1. Identify Addresses

Record these values privately:

| Value | Example format | Purpose |
|---|---|---|
| Home Tailscale IP | `<transmission-tailscale-ip>` | Transmission Tailscale address |
| VPS Tailscale IP | `<vps-tailscale-ip>` | WireGuard endpoint over Tailscale |
| VPS public IP | `<cloud-public-ip>` | Headscale/cloud route exception |
| Home LAN gateway | `<lan-gateway>` | Normal route to VPS public address |
| Transmission WireGuard IP | `<transmission-wireguard-ip>` | Client tunnel address |
| VPS WireGuard IP | `<vps-wireguard-ip>` | Server tunnel address |

Confirm Tailscale first:

```bash
tailscale status
ip -br addr show tailscale0
tailscale ping <vps-tailscale-ip>
```

Do not continue until the VPS responds.

### 2. Configure VPS WireGuard

The VPS WireGuard server must:

- Listen on UDP `51820`.
- Enable IPv4 forwarding.
- Allow forwarding from WireGuard to its internet interface.
- Masquerade WireGuard traffic on internet egress.
- Contain a peer for the Transmission WireGuard public key.

Example server peer values:

```ini
[Peer]
PublicKey = <transmission-public-key>
AllowedIPs = <transmission-wireguard-ip>/32
```

Verify the server peer exists before starting the client:

```bash
wg show
```

### 3. Configure Headscale ACL

Permit Transmission to reach the VPS Tailscale node on WireGuard's UDP port:

```json
{
  "action": "accept",
  "src": ["transmission"],
  "dst": ["cloud:51820"]
}
```

Merge this rule into existing policy. Reload/apply ACL using the method used by your Headscale deployment.

### 4. Configure Tailscale on Transmission

Install and authenticate Tailscale using a short-lived Headscale auth key:

```bash
systemctl enable --now tailscaled
tailscale up \
  --login-server=https://<headscale-hostname> \
  --auth-key=<one-time-auth-key> \
  --accept-dns=false
```

Verify:

```bash
tailscale status
tailscale ping <vps-tailscale-ip>
```

### 5. Configure WireGuard Client

Create `/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address = <transmission-wireguard-ip>/32
PrivateKey = <transmission-private-key>
Table = auto

# Keep WireGuard endpoint reachable through Tailscale.
PostUp = ip route replace <vps-tailscale-ip>/32 dev tailscale0 table main
PreDown = ip route del <vps-tailscale-ip>/32 dev tailscale0 table main 2>/dev/null || true

# Keep Headscale/cloud control traffic outside the full tunnel.
PostUp = ip route replace <cloud-public-ip>/32 via <lan-gateway> dev eth0 onlink table main
PreDown = ip route del <cloud-public-ip>/32 via <lan-gateway> dev eth0 onlink table main 2>/dev/null || true

[Peer]
PublicKey = <vps-wireguard-public-key>
PresharedKey = <preshared-key>
Endpoint = <vps-tailscale-ip>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 10
```

Protect the file:

```bash
chmod 600 /etc/wireguard/wg0.conf
```

The second route exception is needed when Headscale or other Tailscale control traffic uses the VPS public address. Without it, WireGuard can capture Tailscale traffic and take its own transport offline.

### 6. Order Services Correctly

Create `/etc/systemd/system/wg-quick@wg0.service.d/override.conf`:

```ini
[Unit]
Requires=tailscaled.service
After=network-online.target tailscaled.service
Wants=network-online.target
```

Reload systemd:

```bash
systemctl daemon-reload
```

### 7. Start and Test WireGuard

Start Tailscale first, then WireGuard:

```bash
systemctl restart tailscaled
sleep 5
systemctl start wg-quick@wg0
```

Check the client:

```bash
systemctl is-active wg-quick@wg0
wg show
ip rule
ip route get <vps-tailscale-ip>
curl -4sS https://api.ipify.org
```

Healthy state:

- `wg-quick@wg0` is active.
- Client and server show a recent WireGuard handshake.
- WireGuard received bytes increase.
- Route to VPS Tailscale IP uses `tailscale0`.
- Public IP is cloud/VPS egress, not home ISP egress.

### 8. Enable Boot Persistence

Only after manual verification succeeds:

```bash
systemctl enable tailscaled
systemctl enable wg-quick@wg0
```

Reboot once and repeat the checks. If Tailscale goes offline after WireGuard starts, stop WireGuard, restore the two route exceptions, and inspect `journalctl -u wg-quick@wg0`.

### 9. Verify Transmission

```bash
systemctl is-active transmission-daemon
curl -4sS https://api.ipify.org
wg show
```

Transmission's public address must be the VPS/cloud address. If it shows the home ISP address, Transmission traffic is bypassing `wg0`.

## Components

| Component | Address | Role |
|---|---:|---|
| Transmission LXC | `192.*.*.*` / `100.*.*.*` | WireGuard client and Tailscale node |
| kubelab-cloud | `100.*.*.*` | Tailscale node and WireGuard server |
| WireGuard tunnel | `10.*.*.*` -> `10.*.*.*` | Full-tunnel VPN |
| WireGuard Docker stack | `/opt/dockge/stacks/wireguard` | Server configuration |
| Headscale | `https://headscale.<domain>.com` | Tailscale control server |

## Headscale ACL

Transmission belongs to Headscale user `generic@`. Permit it to reach the cloud node:

```json
{
  "hosts": {
    "cloud": "100.*.*.*/32",
    "transmission": "100.*.*.*/32"
  },
  "acls": [
    {
      "action": "accept",
      "src": ["transmission"],
      "dst": ["cloud:*"]
    }
  ],
  "ssh": []
}
```

Merge this rule with existing ACL entries. Do not commit auth keys or private keys.

Create a node key from the Headscale pod when needed:

```bash
kubectl -n headscale exec <headscale-pod> -- \
  headscale preauthkeys create --user 2
```

## Transmission Client

Tailscale must stay enabled because it transports WireGuard:

```bash
systemctl enable --now tailscaled
tailscale up \
  --login-server=https://headscale.<domain>.com \
  --auth-key=<one-time-headscale-auth-key> \
  --accept-dns=false
```

WireGuard client configuration: `/etc/wireguard/wg0.conf`.

Important settings:

```ini
[Interface]
Address = 10.*.*.*
Table = auto
PostUp = ip route replace 100.*.*.*/32 dev tailscale0 table main
PostUp = ip route replace <cloud-public-ip>/32 via <lan-gateway> dev eth0 onlink table main
PreDown = ip route del 100.*.*.*/32 dev tailscale0 table main 2>/dev/null || true
PreDown = ip route del <cloud-public-ip>/32 via <lan-gateway> dev eth0 onlink table main 2>/dev/null || true

[Peer]
Endpoint = 100.*.*.*:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 10
```

Both route exceptions are required. Without them, WireGuard's full-tunnel policy can capture traffic to the Tailscale endpoint or Headscale/cloud public address, causing Tailscale to go offline and WireGuard to lose its handshake.

Replace `<cloud-public-ip>` and `<lan-gateway>` with deployment-specific values. Do not commit real addresses, private keys, preshared keys, or auth keys.

Ensure WireGuard starts after Tailscale:

```ini
# /etc/systemd/system/wg-quick@wg0.service.d/override.conf
[Unit]
Requires=tailscaled.service
After=network-online.target tailscaled.service
Wants=network-online.target
```

Enable services:

```bash
systemctl disable --now wg-quick@wg0  # only when intentionally stopping WG
systemctl enable --now tailscaled
systemctl enable --now wg-quick@wg0
```

Do not disable `tailscaled` while WireGuard endpoint is `100.*.*.*`.

## Server Configuration

The server runs LinuxServer WireGuard in Docker:

```text
/opt/dockge/stacks/wireguard/compose.yaml
/opt/dockge/stacks/wireguard/config/wg_confs/wg0.conf
```

Required server properties:

- UDP `51820` published to the WireGuard container.
- IPv4 forwarding enabled.
- Forwarding accepted between `wg0` and container `eth0`.
- MASQUERADE on container egress interface.
- Peer `10.*.*.*/32` present in server WG configuration.

Because the WG endpoint uses the server's Tailscale address, host rules forward Tailscale UDP `51820` to Docker:

```bash
iptables -t nat -I PREROUTING 1 \
  -i tailscale0 -d 100.*.*.* -p udp --dport 51820 \
  -j DNAT --to-destination <wireguard-container-ip>:51820

iptables -I FORWARD 1 \
  -i tailscale0 -o br-02f23bd46907 -p udp \
  -d <wireguard-container-ip> --dport 51820 -j ACCEPT

iptables -I FORWARD 1 \
  -i br-02f23bd46907 -o tailscale0 -p udp \
  -s <wireguard-container-ip> --sport 51820 -j ACCEPT
```

Persist rules after changes:

```bash
netfilter-persistent save
systemctl enable netfilter-persistent
```

The Docker bridge name or container IP can change after recreation. Check before restoring rules:

```bash
docker network inspect <network-name>
```

## Verification

Run on Transmission:

```bash
tailscale status
systemctl is-active tailscaled
systemctl is-active wg-quick@wg0
wg show
curl -4sk https://api.ipify.org
systemctl is-active transmission-daemon
```

Healthy result:

- Tailscale peer `100.*.*.*` responds.
- WG shows a recent `latest handshake`.
- WG received bytes increase.
- Public IP is cloud/VPS egress, not the home ISP address.
- Transmission service is active.

Run on the server:

```bash
iptables -t nat -L PREROUTING -v -n | grep tailscale0
```

The peer should show `10.*.*.*/32`, recent handshake, and increasing transfer counters.

## Troubleshooting

### No WG handshake

Check in order:

```bash
ip route get 100.*.*.*
wg show
```

Expected endpoint route must use `tailscale0`, not `wg0`. The Headscale/cloud public address must use the normal LAN gateway, not `wg0`.

On the server, check DNAT counters:

```bash
iptables -t nat -L PREROUTING -v -n | grep tailscale0
```

Zero counters indicate Headscale ACL, Tailscale transport, or host filtering. Increasing counters with no WG handshake indicates Docker forwarding or container configuration.

### Internet unavailable

Check:

```bash
wg show
ip rule
ip route
curl -4sk https://api.ipify.org
```

Do not set a Tailscale exit node on Transmission. WireGuard is the intended internet exit layer.

### SSH access lost

This can happen when a full-tunnel route captures the LAN path. Access through Tailscale:

```bash
ssh -i ~/<username>/kubelab.pem root@100.*.*.*
```

Then stop WG temporarily:

```bash
systemctl stop wg-quick@wg0
```

Restore the `100.*.*.*/32` route exception before starting WG again.

## Security Notes

- Treat all WireGuard private keys, preshared keys, and Headscale auth keys as secrets.
- Rotate any key exposed in shell history, chat, logs, or documentation.
- Keep `AllowedIPs = 0.0.0.0/0` only on the Transmission client peer.
- Keep Headscale ACL scope limited to `transmission -> cloud:51820` if other cloud ports are unnecessary.
