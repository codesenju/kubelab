# Mailcow in a Proxmox LXC Behind CGNAT Using Contabo + Headscale/Tailscale + Traefik

> **Sanitized edition:** Public IP addresses, real domains, hostnames, and mailbox addresses have been replaced with documentation/example values.

This guide starts with the **clean setup that works**, based on the lessons learned during troubleshooting.  
If you hit a problem during a step, follow the referenced item in the **Troubleshooting Guide** at the end.

---

# Part 1 — Simple Step-by-Step Setup

## 1. Prepare the Proxmox LXC

Create a dedicated LXC for Mailcow.

A working example:

```text
CPU:        2 cores
Memory:     4 GiB
Root disk:  20 GiB minimum
Network:    static LAN address
Device:     /dev/net/tun
```

For long-term use, allocate more than 20 GiB if you expect significant mail volume, attachments, logs, or backups.

Enable the LXC features needed for Docker:

```text
nesting=1
keyctl=1
```

Expose the TUN device for Tailscale:

```text
/dev/net/tun
```

Verify inside the LXC:

```bash
ls -l /dev/net/tun
```

If Docker fails to work correctly inside the LXC, see **Troubleshooting #1**.

If `/dev/net/tun` is missing, see **Troubleshooting #2**.

---

## 2. Confirm Storage Before Installing Mailcow

Inside the LXC:

```bash
df -h
docker system df
```

On the Proxmox host:

```bash
df -h
pvesm status
```

Make sure the Proxmox storage backing the LXC is not full.

This matters because the LXC can appear to have free space while the Proxmox host storage is exhausted.

If Docker pulls fail with disk-space errors, see **Troubleshooting #3**.

---

## 3. Install Mailcow

Inside the LXC:

```bash
apt update
apt install -y git curl
```

Clone Mailcow:

```bash
cd /opt
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized
./generate_config.sh
```

Use:

```text
MAILCOW_HOSTNAME=mail.example.com
```

Because Traefik will terminate public HTTPS, a practical setting is:

```text
SKIP_LETS_ENCRYPT=y
```

Start Mailcow:

```bash
docker compose pull
docker compose up -d
```

If Mailcow Postfix cannot bind port 25, see **Troubleshooting #4**.

If the Postfix container starts but has no network/DNS connectivity, see **Troubleshooting #5**.

---

## 4. Create the Mail Domain and Mailbox

In Mailcow:

```text
E-Mail
→ Configuration
→ Domains
→ Add domain
```

Add:

```text
example.com
```

Then create a mailbox:

```text
E-Mail
→ Configuration
→ Mailboxes
→ Add mailbox
```

Example:

```text
admin@example.com
```

Use the mailbox credentials for SOGo/webmail.

If Webmail redirects back to the Mailcow dashboard, see **Troubleshooting #6**.

---

## 5. Configure Public DNS

Create these records.

### A record

```text
mail.example.com -> 203.0.113.10
```

If using Cloudflare, use **DNS only**.

### MX

```text
example.com MX 10 mail.example.com.
```

### SPF

```text
example.com TXT "v=spf1 ip4:203.0.113.10 -all"
```

### DMARC

```text
_dmarc.example.com TXT "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com; adkim=s; aspf=s"
```

### PTR / Reverse DNS

At the VPS provider, configure:

```text
203.0.113.10 -> mail.example.com
```

Verify:

```bash
dig +short mail.example.com A
dig +short MX example.com
dig +short TXT example.com
dig +short TXT _dmarc.example.com
dig -x 203.0.113.10 +short
```

Expected PTR:

```text
mail.example.com.
```

If PTR, A, HELO, or SPF do not line up, see **Troubleshooting #7**.

---

## 6. Configure DKIM

In Mailcow:

```text
System
→ Configuration
→ Options
→ ARC/DKIM keys
```

Create a key:

```text
Domain:   example.com
Selector: dkim
Key size: 2048
```

Publish the TXT record:

```text
dkim._domainkey.example.com
```

with the complete public key shown by Mailcow.

Verify:

```bash
dig TXT dkim._domainkey.example.com +short
```

Long TXT records may appear as multiple quoted strings. That is normal.

If Mailcow refuses to create the DKIM key, confirm the domain was added first and see **Troubleshooting #8**.

---

## 7. Configure Traefik for the Mailcow Web UI

Keep public ports **80 and 443** owned by Traefik.

Do **not** DNAT 80/443 directly to Mailcow.

Use a selectorless Service and EndpointSlice pointing to Mailcow HTTPS.

### EndpointSlice

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: mailcow
  namespace: public
  labels:
    kubernetes.io/service-name: mailcow
addressType: IPv4
ports:
  - name: https
    protocol: TCP
    port: 443
endpoints:
  - addresses:
      - 192.168.1.32
```

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mailcow
  namespace: public
spec:
  ports:
    - name: https
      port: 443
      targetPort: 443
      protocol: TCP
      appProtocol: https
```

### HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mailcow
  namespace: public
spec:
  parentRefs:
    - name: local-gateway
      namespace: traefik
      sectionName: web-2
    - name: local-gateway
      namespace: traefik
      sectionName: websecure-2
  hostnames:
    - mail.example.com
  rules:
    - backendRefs:
        - name: mailcow
          port: 443
```

Important: proxy to Mailcow **HTTPS port 443**, not port 80.

If you get a Traefik 404, see **Troubleshooting #9**.

If you get `ERR_TOO_MANY_REDIRECTS`, see **Troubleshooting #10**.

---

## 8. Enable Mail Port Forwarding on the VPS

Enable IP forwarding:

```bash
cat >/etc/sysctl.d/99-mail-forward.conf <<'EOF'
net.ipv4.ip_forward=1
EOF

sysctl --system
```

DNAT only mail protocols:

```bash
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 25 \
  -j DNAT --to-destination 192.168.1.32:25

iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 465 \
  -j DNAT --to-destination 192.168.1.32:465

iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 587 \
  -j DNAT --to-destination 192.168.1.32:587

iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 993 \
  -j DNAT --to-destination 192.168.1.32:993

iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 4190 \
  -j DNAT --to-destination 192.168.1.32:4190
```

Allow forwarding:

```bash
iptables -A FORWARD -d 192.168.1.32/32 -i eth0 -p tcp --dport 25 -j ACCEPT
iptables -A FORWARD -d 192.168.1.32/32 -i eth0 -p tcp --dport 465 -j ACCEPT
iptables -A FORWARD -d 192.168.1.32/32 -i eth0 -p tcp --dport 587 -j ACCEPT
iptables -A FORWARD -d 192.168.1.32/32 -i eth0 -p tcp --dport 993 -j ACCEPT
iptables -A FORWARD -d 192.168.1.32/32 -i eth0 -p tcp --dport 4190 -j ACCEPT
```

Add return-path masquerading:

```bash
iptables -t nat -A POSTROUTING \
  -d 192.168.1.32 \
  -p tcp \
  -m multiport \
  --dports 25,465,587,993,4190 \
  -j MASQUERADE
```

Do not include ports 80/443 here.

If public SMTP does not reach Mailcow, see **Troubleshooting #11**.

---

## 9. Open the VPS Provider Firewall

Allow:

```text
25    TCP
465   TCP
587   TCP
993   TCP
4190  TCP
80    TCP
443   TCP
```

Test externally:

```bash
nc -zv 203.0.113.10 25
nc -zv 203.0.113.10 465
nc -zv 203.0.113.10 587
nc -zv 203.0.113.10 993
```

If the VPS sees no incoming packets at all, see **Troubleshooting #12**.

---

## 10. Install Tailscale in the Mailcow LXC

Start Tailscale:

```bash
systemctl enable --now tailscaled
```

Join Headscale:

```bash
tailscale up \
  --login-server=https://headscale.example.net \
  --accept-routes \
  --hostname=mailserver
```

Example Mailcow Tailscale IP:

```text
100.64.0.11
```

Verify:

```bash
tailscale status
tailscale ping 100.64.0.10
```

If Tailscale cannot start or create its tunnel, see **Troubleshooting #2**.

---

## 11. Add the Headscale ACL for the SMTP Relay

Example ACL:

```json
{
  "groups": {},
  "tagOwners": {},
  "hosts": {
    "contabo": "100.64.0.10/32",
    "mailserver": "100.64.0.11/32"
  },
  "acls": [
    {
      "action": "accept",
      "src": ["mailserver"],
      "dst": ["contabo:2525"]
    }
  ],
  "ssh": []
}
```

After applying the policy, verify from Mailcow:

```bash
nc -zv 100.64.0.10 2525 -w 3
```

If it times out while `tailscale ping` works, see **Troubleshooting #13**.

---

## 12. Install the Outbound Postfix Relay on Contabo

First verify the VPS can reach external MX servers on TCP/25:

```bash
nc -zv gmail-smtp-in.l.google.com 25
```

Install Postfix:

```bash
apt update
apt install -y postfix
```

During setup, a temporary system mail name such as:

```text
relay.example.com
```

is fine.

Then configure the public SMTP identity:

```bash
postconf -e 'myhostname = mail.example.com'
postconf -e 'inet_interfaces = 100.64.0.10, 127.0.0.1'
postconf -e 'inet_protocols = ipv4'
postconf -e 'smtp_address_preference = ipv4'
postconf -e 'mydestination = localhost'
postconf -e 'relayhost ='
postconf -e 'smtpd_relay_restrictions = permit_mynetworks,reject_unauth_destination'
postconf -e 'mynetworks = 127.0.0.0/8, 100.64.0.11/32'
```

If `postfix check` reports `loopback-only` as a hostname, see **Troubleshooting #14**.

If Postfix restart fails with `Too many open files`, see **Troubleshooting #15**.

---

## 13. Add the Private Relay Listener on Port 2525

Edit:

```bash
nano /etc/postfix/master.cf
```

Add:

```text
2525      inet  n       -       y       -       -       smtpd
```

Validate and start:

```bash
postfix check
postfix start
```

Verify:

```bash
ss -lntp | grep -E ':25|:2525'
```

Expected:

```text
100.64.0.10:25
100.64.0.10:2525
127.0.0.1:25
127.0.0.1:2525
```

If 2525 is not listening, see **Troubleshooting #16**.

---

## 14. Verify Relay Permission Manually

From Mailcow:

```bash
telnet 100.64.0.10 2525
```

Enter one line at a time:

```text
EHLO mail.example.com
MAIL FROM:<admin@example.com>
RCPT TO:<user@gmail.com>
```

Expected response:

```text
250 2.1.5 Ok
```

Exit:

```text
QUIT
```

If you accidentally get syntax errors because commands and server responses were mixed together, see **Troubleshooting #17**.

---

## 15. Configure Mailcow to Use the Contabo Relay

In Mailcow:

```text
System
→ Configuration
→ Routing
→ Add sender-dependent transport
```

Use:

```text
Host: [100.64.0.10]:2525
Username: blank
Password: blank
```

Then:

```text
E-Mail
→ Configuration
→ Domains
→ example.com
```

Select:

```text
ID 1: [100.64.0.10]:2525
```

under **Sender-dependent transports**.

Leave:

```text
Relay this domain
Relay all recipients
```

unchecked.

If Mailcow still sends directly from your home/CGNAT IP, see **Troubleshooting #18**.

---

## 16. Verify Outbound Delivery

Send a message from:

```text
admin@example.com
```

to Gmail.

Watch Mailcow:

```bash
cd /opt/mailcow-dockerized
docker compose logs -f postfix-mailcow
```

Expected:

```text
relay=100.64.0.10[100.64.0.10]:2525
status=sent
```

On Contabo:

```bash
grep -Ei 'postfix|status=|bounced|deferred' /var/log/mail.log
```

If the Mailcow queue is empty but the recipient got nothing, see **Troubleshooting #19**.

---

## 17. Verify Public HELO and Sending IP

Set Contabo Postfix:

```bash
postconf -e 'myhostname = mail.example.com'
postfix reload
```

Verify:

```bash
postconf myhostname
```

Expected:

```text
myhostname = mail.example.com
```

Send a test from SOGo:

```text
To: helocheck@abuseat.org
```

A successful diagnostic result should report something equivalent to:

```text
The HELO for IP address 203.0.113.10 was 'mail.example.com' (valid syntax)
```

This confirms:

```text
HELO: mail.example.com
PTR:  203.0.113.10 -> mail.example.com
A:    mail.example.com -> 203.0.113.10
```

If your IP has historical bad HELOs or poor reputation, see **Troubleshooting #20**.

---

## 18. Configure the Trusted Inbound Forwarding Host

Because the current NAT/Tailscale path hides the original internet sender IP, Mailcow sees the forwarding hop instead.

Example:

```text
192.168.1.31
```

In Mailcow:

```text
System
→ Configuration
→ Options
→ Forwarding Hosts
```

Add:

```text
192.168.1.31/32
```

Set:

```text
Spam filter: Inactive
```

Restart:

```bash
cd /opt/mailcow-dockerized
docker compose restart postfix-mailcow rspamd-mailcow
```

Verify:

```text
whitelist_forwardinghosts: ... result 200 PERMIT
postfix/postscreen: ALLOWLISTED [...]
```

If inbound Gmail is greylisted or lands in Junk, see **Troubleshooting #21**.

---

## 19. Remove the Temporary Global Greylisting Override

During troubleshooting, greylisting may have been globally disabled with:

```bash
cat > data/conf/rspamd/override.d/greylist.conf <<'EOF'
enabled = false;
EOF
```

Once the trusted forwarding host is configured correctly, remove that global override:

```bash
cd /opt/mailcow-dockerized
rm -f data/conf/rspamd/override.d/greylist.conf
docker compose restart rspamd-mailcow
```

The forwarding host remains trusted and bypasses greylisting, while normal greylisting behavior is restored globally.

If greylisting returns for the trusted forwarding host, see **Troubleshooting #21**.

---

## 20. Verify Inbound Mail

Send a Gmail message to:

```text
admin@example.com
```

Watch Mailcow:

```bash
docker compose logs -f postfix-mailcow
```

Successful local delivery looks like:

```text
to=<admin@example.com>
relay=dovecot[...]:24
dsn=2.0.0
status=sent
```

and:

```text
Saved
```

Confirm the message lands in **Inbox**, not Junk.

If the VPS receives Gmail but Mailcow does not, see **Troubleshooting #11**.

If Mailcow accepts it but it lands in Junk, see **Troubleshooting #21**.

---

## 21. Final Verification

Verify DNS:

```bash
dig A mail.example.com +short
dig MX example.com +short
dig TXT example.com +short
dig TXT _dmarc.example.com +short
dig TXT dkim._domainkey.example.com +short
dig -x 203.0.113.10 +short
```

Verify public SMTP:

```bash
nc -zv mail.example.com 25
```

Verify relay:

```bash
nc -zv 100.64.0.10 2525
```

Verify Mailcow queue:

```bash
docker compose exec postfix-mailcow postqueue -p
```

Send one message each direction.

### Expected final state

```text
Mailcow web UI:        working
SOGo webmail:          working
Inbound SMTP:          working
Outbound SMTP:         working through VPS relay
SPF:                   configured
DKIM:                  configured
DMARC:                 configured
PTR:                   configured
HELO:                  mail.example.com
Trusted forwarder:     configured
Greylisting override:  removed
Inbox delivery:        working
```

For Gmail-delivery reputation problems, see **Troubleshooting #20**.

---

# Part 2 — Numbered Troubleshooting Guide

## Troubleshooting #1 — Docker Inside the Proxmox LXC Does Not Work

Confirm the LXC has:

```text
nesting=1
keyctl=1
```

Check the Proxmox container configuration and restart the LXC after changing features.

Remember the troubleshooting layers:

```text
Proxmox host
→ LXC
→ Docker
→ Mailcow containers
```

Do not assume every Docker failure originates inside Mailcow.

---

## Troubleshooting #2 — Tailscale Cannot Create `/dev/net/tun`

Inside the LXC:

```bash
ls -l /dev/net/tun
```

If missing, expose `/dev/net/tun` from Proxmox to the LXC.

A working Proxmox UI will show something similar to:

```text
Device (dev0): /dev/net/tun
```

Restart the LXC after adding it.

---

## Troubleshooting #3 — Docker Pull Says No Space Left but the LXC Has Free Space

Check both layers.

Inside LXC:

```bash
df -h
docker system df
```

On Proxmox:

```bash
df -h
pvesm status
```

The backing Proxmox storage may be full even when the LXC filesystem appears to have free space.

Free or expand the Proxmox storage.

---

## Troubleshooting #4 — Mailcow Postfix Cannot Bind Port 25

Check:

```bash
ss -lntp | grep ':25'
```

If Ubuntu host Postfix is already using port 25:

```bash
systemctl stop postfix
systemctl disable postfix
```

Then:

```bash
cd /opt/mailcow-dockerized
docker compose up -d
```

---

## Troubleshooting #5 — Mailcow Postfix Container Has No Docker Network

Check:

```bash
docker inspect mailcowdockerized-postfix-mailcow-1 \
  --format '{{json .NetworkSettings.Networks}}'
```

If it returns:

```json
{}
```

force-recreate it:

```bash
cd /opt/mailcow-dockerized
docker compose up -d --force-recreate postfix-mailcow
```

Then verify SMTP ports and DNS again.

---

## Troubleshooting #6 — SOGo Opens and Redirects Back to Mailcow

Use a real mailbox account, not the Mailcow system admin account.

Create:

```text
admin@example.com
```

under:

```text
E-Mail
→ Configuration
→ Mailboxes
```

Then log in with that mailbox identity.

---

## Troubleshooting #7 — SPF/PTR/HELO Do Not Align

The public SMTP identity should line up:

```text
A:    mail.example.com -> 203.0.113.10
PTR:  203.0.113.10 -> mail.example.com
HELO: mail.example.com
SPF:  authorizes 203.0.113.10
```

Verify:

```bash
dig +short mail.example.com A
dig -x 203.0.113.10 +short
postconf myhostname
```

---

## Troubleshooting #8 — DKIM Creation Fails

Make sure the domain exists first:

```text
E-Mail
→ Configuration
→ Domains
```

Then generate the DKIM key.

Publish:

```text
dkim._domainkey.example.com
```

and verify:

```bash
dig TXT dkim._domainkey.example.com +short
```

---

## Troubleshooting #9 — Traefik Returns 404

Confirm you are applying resources to the **correct Kubernetes cluster**.

Then inspect the real Gateway:

```bash
kubectl get gateway -A
kubectl get gateway -n traefik local-gateway -o yaml
```

Make sure the HTTPRoute uses the correct:

```text
namespace
Gateway name
sectionName
hostname
```

---

## Troubleshooting #10 — `ERR_TOO_MANY_REDIRECTS`

Cause:

```text
Traefik HTTPS
→ Mailcow HTTP :80
→ Mailcow redirects to HTTPS
→ Traefik
→ loop
```

Fix the backend to use:

```text
192.168.1.32:443
```

with:

```yaml
appProtocol: https
```

---

## Troubleshooting #11 — Gmail Reaches the VPS but Mailcow Does Not Receive It

Check DNAT:

```bash
iptables -t nat -S PREROUTING | grep -- '--dport 25'
```

Check forwarding:

```bash
iptables -S FORWARD | grep 192.168.1.32
```

Capture public SMTP:

```bash
tcpdump -ni eth0 tcp port 25
```

Then monitor Mailcow:

```bash
docker compose logs -f postfix-mailcow
```

If packets reach the VPS but not Mailcow, investigate the Tailscale/subnet-routing and firewall path.

---

## Troubleshooting #12 — External SMTP Gets `Connection refused` or No Packets Reach the VPS

If:

```bash
tcpdump -ni eth0 tcp port 25
```

shows nothing while testing externally, check the VPS provider firewall.

Allow:

```text
25
465
587
993
4190
```

plus 80/443 for Traefik.

---

## Troubleshooting #13 — `tailscale ping` Works but TCP/2525 Times Out

This usually indicates a Headscale ACL problem.

Use explicit host aliases:

```json
"contabo": "100.64.0.10/32",
"mailserver": "100.64.0.11/32"
```

and:

```json
{
  "action": "accept",
  "src": ["mailserver"],
  "dst": ["contabo:2525"]
}
```

After applying the policy:

```bash
nc -zv 100.64.0.10 2525 -w 3
```

---

## Troubleshooting #14 — `inet_interfaces: host not found: loopback-only`

This is invalid when combined with another address:

```text
inet_interfaces = 100.64.0.10, loopback-only
```

Use:

```bash
postconf -e 'inet_interfaces = 100.64.0.10, 127.0.0.1'
```

Then:

```bash
postfix check
```

---

## Troubleshooting #15 — Postfix Restart Fails With `Too Many Open Files`

Check global file descriptors:

```bash
cat /proc/sys/fs/file-nr
cat /proc/sys/fs/file-max
```

If those are healthy, inspect inotify:

```bash
sysctl fs.inotify.max_user_instances
sysctl fs.inotify.max_user_watches
sysctl fs.inotify.max_queued_events
```

A k0s/containerd VPS may exhaust the default instance limit.

Fix:

```bash
cat >/etc/sysctl.d/99-inotify.conf <<'EOF'
fs.inotify.max_user_instances=1024
fs.inotify.max_user_watches=524288
fs.inotify.max_queued_events=32768
EOF

sysctl --system
```

Then restart Postfix.

---

## Troubleshooting #16 — Port 2525 Is Not Listening

Check:

```bash
grep '^2525' /etc/postfix/master.cf
```

Expected:

```text
2525      inet  n       -       y       -       -       smtpd
```

Then:

```bash
postfix check
postfix stop
postfix start
ss -lntp | grep 2525
```

---

## Troubleshooting #17 — Manual Telnet SMTP Test Gives Syntax Errors

Wait for the server response after each command.

Correct sequence:

```text
EHLO mail.example.com
```

wait for the final `250` line, then:

```text
MAIL FROM:<admin@example.com>
```

wait, then:

```text
RCPT TO:<user@gmail.com>
```

Expected:

```text
250 2.1.5 Ok
```

Exit:

```text
QUIT
```

To escape Telnet manually:

```text
Ctrl + ]
telnet> quit
```

---

## Troubleshooting #18 — Gmail Rejects Outbound Mail From the Home/CGNAT IP

A rejection such as:

```text
550 5.7.1 The IP you're using to send mail is not authorized
```

means Mailcow is still sending directly.

Check Mailcow logs.

Wrong:

```text
relay=gmail-smtp-in...
```

Correct:

```text
relay=100.64.0.10[100.64.0.10]:2525
```

Configure the sender-dependent transport and assign it to the domain.

---

## Troubleshooting #19 — Mailcow Queue Is Empty but the Message Never Arrived

An empty queue does not prove successful delivery.

Search logs:

```bash
docker compose logs postfix-mailcow | \
grep -Ei 'status=|bounced|deferred|sent|reject'
```

`status=bounced` means the message already left the queue because it permanently failed.

On the VPS relay:

```bash
grep -Ei 'status=|bounced|deferred' /var/log/mail.log
```

---

## Troubleshooting #20 — Gmail Delivers Outbound Mail to Spam / IP Reputation Problems

First verify Gmail's **Show original** reports:

```text
SPF:   PASS
DKIM:  PASS
DMARC: PASS
```

Verify the source IP is your VPS public IP.

Check:

```text
Google Postmaster Tools
Spamhaus Reputation Checker
MXToolbox blacklist checker
```

A newly assigned VPS IP may have historical reputation issues from a previous user.

A HELO checker can confirm the current identity:

```text
helocheck@abuseat.org
```

The desired identity is:

```text
Public IP -> PTR -> mail.example.com
mail.example.com -> A -> same public IP
HELO -> mail.example.com
```

Even after technical fixes, a new domain/IP can take time to build reputation.

---

## Troubleshooting #21 — Inbound Gmail Is Greylisted or Lands in Junk

If Mailcow sees every internet sender as the same internal forwarding IP, for example:

```text
192.168.1.31
```

add it under:

```text
System
→ Configuration
→ Options
→ Forwarding Hosts
```

Use:

```text
192.168.1.31/32
Spam filter: Inactive
```

Then:

```bash
docker compose restart postfix-mailcow rspamd-mailcow
```

Expected:

```text
whitelist_forwardinghosts: ... 200 PERMIT
postfix/postscreen: ALLOWLISTED [...]
```

If you temporarily created:

```text
data/conf/rspamd/override.d/greylist.conf
```

with:

```text
enabled = false;
```

remove it once the trusted forwarding host is working:

```bash
rm -f data/conf/rspamd/override.d/greylist.conf
docker compose restart rspamd-mailcow
```

This restores normal greylisting globally while keeping the trusted forwarding hop exempt.

---

# Architectural Limitation

The current inbound NAT/Tailscale path hides the original SMTP sender IP.

Mailcow may see:

```text
192.168.1.31
```

instead of the real sender, such as Google's SMTP IP.

The trusted-forwarding-host configuration makes the deployment practical and functional, but Rspamd cannot perform perfect sender-IP reputation checks.

A future improvement would preserve the original client IP or use a supported SMTP proxy/relay design that conveys the original sender IP safely.

