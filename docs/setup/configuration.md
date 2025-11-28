# Configuration

## Ansible Vault Setup

All sensitive configuration is stored in an encrypted Ansible Vault file.

### Create Secrets File

1. **Create the secrets file**:
   ```bash
   cd ansible
   touch group_vars/all/secrets.yaml
   ```

2. **Add your secrets** (see [Required Variables](#required-variables) below)

3. **Encrypt the file**:
   ```bash
   ansible-vault encrypt group_vars/all/secrets.yaml
   ```
   
   You'll be prompted to create a vault password. Store this securely!

### Alternative: Use Password File

```bash
# Create password file
echo "your-secure-password" > vault-pass.txt
chmod 600 vault-pass.txt

# Encrypt with password file
ansible-vault encrypt group_vars/all/secrets.yaml --vault-password-file vault-pass.txt
```

**Important**: Add `vault-pass.txt` to `.gitignore` to prevent committing it!

### Edit Encrypted File

```bash
ansible-vault edit group_vars/all/secrets.yaml --vault-password-file vault-pass.txt
```

## Required Variables

### ArgoCD Configuration
```yaml
argocd_openid_client_secret: "<your-client-secret>"
argocd_openid_issuer_url: "<your-openid-issuer-url>"
argocd_openid_redirect_uri: "<your-redirect-uri>"
argocd_domain: "argocd.local.jazziro.com"
```

### Cloudflared Configuration
```yaml
cloudflared_hostname_1: "*.local.jazziro.com"
cloudflared_hostname_2: "grafana.local.jazziro.com"
cloudflared_hostname_3: "prometheus.local.jazziro.com"
cloudflared_hostname_4: "argocd.local.jazziro.com"
cloudflared_hostname_5: "minio.local.jazziro.com"
```

### Database Configuration
```yaml
db_encryption_key: "<generate-random-32-char-string>"
authentik_secret_key: "<generate-random-50-char-string>"
authentik_postgresql_password: "<strong-password>"
```

### S3/MinIO Configuration
```yaml
s3_access_key: "<minio-access-key>"
s3_secret_key: "<minio-secret-key>"
s3_endpoint: "s3.local.jazziro.com"
```

### Ingress Configuration
```yaml
ingress_httpd_test_host: "test.local.jazziro.com"
```

### Gitea Configuration
```yaml
gitea_db_name: "gitea"
gitea_db_password: "<strong-password>"
gitea_db_user: "gitea"
gitea_db_repmgr_password: "<strong-password>"
gitea_admin_username: "admin"
gitea_admin_password: "<strong-password>"
gitea_admin_email: "admin@local.jazziro.com"
gitea_domain: "gitea.local.jazziro.com"
gitea_registration_token: "<generate-token>"
gitea_instance_url: "https://gitea.local.jazziro.com"
```

## Generating Secure Values

### Random Strings
```bash
# 32-character string
openssl rand -base64 32

# 50-character string
openssl rand -base64 50 | cut -c1-50
```

### Strong Passwords
```bash
# Generate strong password
openssl rand -base64 24
```

### Gitea Registration Token
```bash
# Generate UUID
uuidgen
```

## OpenTofu Variables

Edit `tofu/local.tf` to configure VM settings:

```hcl
locals {
  vm_config = {
    control_plane_1 = {
      name        = "k8s-control-plane-1"
      target_node = "proxmox-node-1"
      ip_address  = "192.168.0.41"
      cores       = 4
      memory      = 8192
      disk_size   = "100G"
    }
    # ... more VMs
  }
}
```

## Inventory Configuration

Edit `ansible/inventory.ini`:

```ini
[control_plane]
k8s-control-plane-1 ansible_host=192.168.0.41
k8s-control-plane-2 ansible_host=192.168.0.42

[workers]
k8s-worker-1 ansible_host=192.168.0.51
k8s-worker-2 ansible_host=192.168.0.52

[lb]
k8s-lb ansible_host=192.168.0.40

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_rsa
```

## Domain Configuration

Update domain names throughout the configuration to match your setup:

1. **DNS Records**: Ensure your DNS provider can resolve your domains
2. **Cert Manager**: Update certificate issuers if using Let's Encrypt
3. **Ingress Resources**: Update host fields in ingress definitions

## Next Steps

After configuration is complete:
1. Verify all secrets are encrypted
2. Test Ansible connectivity: `ansible all -m ping`
3. Proceed to [Installation](installation.md)
