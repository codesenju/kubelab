# 🛠 How We Fixed Internet Access Through Tailscale Exit Node (`kubelab-cloud`)

## Problem
When setting `kubelab-cloud` as a Tailscale exit node, devices could not access the internet and showed `ERR_CONNECTION_TIMED_OUT`.

---

## Root Causes
- Incorrect network interface used for NAT (was assuming `eth0`, real interface was `enp0s6`).
- Missing NAT (Masquerade) iptables rule for proper internet routing.
- Need to ensure IP forwarding was enabled.
- Cloud firewall (Oracle) needed to allow outbound traffic.

---

## Solution Steps

### 1. Find the correct public network interface
```bash
ip route get 8.8.8.8
```
Look for the dev field (e.g., enp0s6).

### 2. Enable IP forwarding
Enable temporary (until reboot):
```bash
sudo sysctl -w net.ipv4.ip_forward=1
```
```bash
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 3. Set up NAT (Masquerade) on the correct interface
First, delete any wrong rules (optional):
```bash
sudo iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null
```
Then add correct MASQUERADE rule for the correct interface (example: enp0s6):
```bash
sudo iptables -t nat -A POSTROUTING -o enp0s6 -j MASQUERADE
```

### 4. (Optional) Make iptables rules persistent
Install persistence tools:
```bash
sudo apt install iptables-persistent
```
Save the current iptables rules:
``bash
sudo netfilter-persistent save
```
Or manually:
```bash
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

### 5. Confirm Tailscale settings
- Ensure your device (laptop, phone, etc.) has selected kubelab-cloud as the exit node.
- Confirm Tailscale ACLs (autoApprovers) allow you to use an exit node.

### 6. Check Cloud Firewall Rules
- Make sure your cloud provider (e.g., Oracle Cloud) allows outbound traffic (0.0.0.0/0) from your VM.
