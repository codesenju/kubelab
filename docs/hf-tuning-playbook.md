# Nexus HF Tuning Playbook

This guide explains how to set up and run `addons/hf-tuning.yaml` to tune the Nexus Hugging Face proxy repository for large GGUF downloads.

## What the playbook changes

Target repository: `hf`

- `httpClient.connection.timeout` -> `300`
- `httpClient.connection.retries` -> `5`
- `proxy.metadataMaxAge` -> `10080` (7 days)
- `negativeCache.timeToLive` -> `60`

The playbook preserves existing Nexus settings (blob store, cleanup policy, routing rule, replication, and other fields).

## Prerequisites

- Nexus is reachable at `https://registry.local.jazziro.com`
- Repository `hf` exists in Nexus
- Ansible is installed locally
- You can run playbooks against `k8s-control-plane-1`
- Nexus admin credentials are available

## Credential setup

Set the Nexus admin password via environment variable (recommended for local runs):

```bash
export NEXUS_ADMIN_PASSWORD='<your-nexus-admin-password>'
```

Optional (if using a non-default admin username):

```bash
export NEXUS_ADMIN_USER='admin'
```

You can also provide credentials through inventory/group vars instead of environment variables.

## Run the playbook

```bash
ansible-playbook -i ansible/inventory.ini addons/hf-tuning.yaml
```

## Optional overrides

Override defaults at runtime with `-e`:

```bash
ansible-playbook -i ansible/inventory.ini addons/hf-tuning.yaml \
  -e hf_http_timeout_seconds=240 \
  -e hf_http_retries=4 \
  -e hf_proxy_metadata_max_age_minutes=4320 \
  -e hf_negative_cache_ttl_minutes=30
```

## Verify the applied configuration

```bash
curl -sk -u 'admin:<password>' \
  'https://registry.local.jazziro.com/service/rest/v1/repositories/huggingface/proxy/hf'
```

Check these fields in the response:

- `.httpClient.connection.timeout`
- `.httpClient.connection.retries`
- `.proxy.metadataMaxAge`
- `.negativeCache.timeToLive`

## Troubleshooting

- `Set nexus_admin_password ...` assertion failure:
  - Export `NEXUS_ADMIN_PASSWORD` or set `nexus_admin_password` in inventory vars.
- Host not matched / inventory warnings:
  - Ensure `-i ansible/inventory.ini` is provided and `k8s-control-plane-1` exists in inventory.
- TLS errors with custom certs:
  - Current playbook uses `validate_certs: false`. If you later enforce cert validation, add trusted CA setup first.
