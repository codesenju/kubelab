# NPM Advanced Configurations
```json
location /{
    proxy_pass http://192.168.0.99:8084; # headscale
}

location ^~ /admin/ {
proxy_pass http://192.168.0.99:8000/admin/; # headscale-admin
}

location ^~ /web/ {
proxy_pass https://192.168.0.99:5443/web/; # headscale-ui
}

```
# Tailscale Exit Node Setup: Full Solution
## 1. Ubuntu Exit Node Configuration
### A) Enable IP Forwarding
```bash
# Edit sysctl config
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-tailscale.conf
echo "net.ipv6.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.d/99-tailscale.conf
```
- Apply changes
```bash
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```
### B) Add NAT Masquerade Rule
```bash
# Find main internet interface (e.g., eth0)
DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}')

# Add NAT rule
sudo iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE

# Make persistent
sudo apt install iptables-persistent -y
sudo netfilter-persistent save
```
### C) Advertise Exit Node
```bash
sudo tailscale up --advertise-exit-node
```
## 2. Tailscale ACL Updates
Modified ACL Policy
```json
json
{
  "autoApprovers": {
    "exitNode": ["group:admins"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["*:*"]
    }
  ]
}
```
Applied via Tailscale Admin Console.

## 3. Windows Client Fixes
A) Set Exit Node
```powershell
tailscale up --exit-node=100.64.0.5 --reset
```
B) Firewall Rules
```powershell
# Temporary test
Set-NetFirewallProfile -Profile Domain,Public,P``rivate -Enabled False
``
# Permanent fix (if needed)
New-NetFirewallRule -DisplayName "Allow Tailscale" -Program "C:\Program Files\Tailscale\tailscale.exe" -Action Allow
```
### C) Clear DNS Cache
```powershell
ipconfig /flushdns
```
## 4. Verification
On Ubuntu
```bash
# Check NAT
sudo iptables -t nat -L POSTROUTING -v | grep MASQUERADE

# Monitor traffic
sudo tcpdump -i eth0 -n host 8.8.8.8
```
On Windows
```powershell
# Confirm exit node
tailscale status

# Test internet
curl ifconfig.me  # Should show Ubuntu's IP
ping 8.8.8.8
```

# **Key Fixes Summary**

| Issue                  | Solution                                                                 | Command/Code Example                                                                 |
|------------------------|--------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| Missing NAT Rule       | Added MASQUERADE rule for outbound traffic                              | `sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE`                         |
| IP Forwarding Disabled | Enabled IPv4/IPv6 forwarding in kernel                                  | `echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-tailscale.conf`                   |
| ACL Restrictions       | Added auto-approval for exit nodes and admin group routing              | Added `"autoApprovers": {"exitNode": ["group:admins"]}` to ACL policy                |
| Windows Firewall Block | Allowed Tailscale traffic through Windows Defender                       | `New-NetFirewallRule -DisplayName "Allow Tailscale" -Program "C:\Program Files\Tailscale\tailscale.exe" -Action Allow` |
| DNS Cache Issues       | Flushed DNS cache to resolve domain resolution failures                 | `ipconfig /flushdns`                                                                |
| Docker Conflicts       | Temporarily stopped Docker to isolate NAT conflicts                     | `sudo systemctl stop docker`                                                        |
| Browser Access Denied  | Disabled firewall temporarily to confirm blocking                       | `Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False`              |