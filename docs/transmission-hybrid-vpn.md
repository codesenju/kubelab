# Transmission Hybrid VPN Guide

## Summary

Transmission runs two VPN layers:

```text
Transmission LXC (192.*.*.*)
  -> WireGuard full-tunnel (10.*.*.*)
  -> Tailscale transport (100.*.*.* -> 100.*.*.*)
  -> kubelab-cloud WireGuard server
  -> Internet
```

WireGuard carries Transmission's internet traffic. Tailscale only transports the WireGuard handshake and encrypted packets to the remote server, avoiding LAN router hairpin NAT.

Expected public IP from Transmission: `129.*.*.*`.

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
PreDown = ip route del 100.*.*.*/32 dev tailscale0 table main 2>/dev/null || true

[Peer]
Endpoint = 100.*.*.*:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 10
```

The route exception is required. Without it, WireGuard's full-tunnel route can send the WireGuard endpoint into `wg0`, creating a routing loop.

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
  -j DNAT --to-destination 172.22.0.2:51820

iptables -I FORWARD 1 \
  -i tailscale0 -o br-02f23bd46907 -p udp \
  -d 172.22.0.2 --dport 51820 -j ACCEPT

iptables -I FORWARD 1 \
  -i br-02f23bd46907 -o tailscale0 -p udp \
  -s 172.22.0.2 --sport 51820 -j ACCEPT
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
- Public IP is `129.*.*.*`, not the home ISP address.
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

Expected route must use `tailscale0`, not `wg0`.

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
