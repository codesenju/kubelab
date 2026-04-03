# Hugging Face Downloads Through Nexus Proxy

Use this flow to pull Hugging Face models through the Nexus `hf` proxy repository.

## Prerequisites

- Nexus HF proxy repository is reachable at `https://registry.local.jazziro.com/repository/hf`
- You have valid Nexus credentials
- `huggingface_hub` CLI (`hf`) is installed

## Download Command (Recommended)

```bash
export NEXUS_USER='<nexus-username>'
export NEXUS_PASS_ENC='<url-encoded-password>'
export HF_ENDPOINT="https://${NEXUS_USER}:${NEXUS_PASS_ENC}@registry.local.jazziro.com/repository/hf"
export HF_HUB_DOWNLOAD_TIMEOUT=1800
export HF_HUB_ETAG_TIMEOUT=60
hf download unsloth/Qwen3.5-9B-GGUF --include "Qwen3.5-9B-Q4_K_M.gguf"
```

## Why these environment variables matter

- `HF_ENDPOINT`: Routes `hf` traffic to Nexus instead of `huggingface.co`
- `HF_HUB_DOWNLOAD_TIMEOUT=1800`: Prevents read timeouts for large files (GGUF can be several GB)
- `HF_HUB_ETAG_TIMEOUT=60`: Gives metadata/etag checks more time on slower links

## Important notes

- URL-encode special characters in the password before placing it in `HF_ENDPOINT` (for example, `@` becomes `%40`).
- This command downloads only one file (`Qwen3.5-9B-Q4_K_M.gguf`) via `--include`.

## Nexus proxy tuning for large GGUF downloads

If you observe repeated HEAD timeouts before the download starts, tune the `hf` proxy repository:

- `httpClient.connection.timeout`: `300`
- `httpClient.connection.retries`: `5`
- `proxy.metadataMaxAge`: `10080` (minutes)
- `negativeCache.timeToLive`: `60` (minutes)

You can verify current settings with:

```bash
curl -sk -u '<admin-user>:<admin-password>' \
  'https://registry.local.jazziro.com/service/rest/v1/repositories/huggingface/proxy/hf'
```

For reliability on big files, also set:

```bash
export HF_HUB_DOWNLOAD_TIMEOUT=1800
export HF_HUB_ETAG_TIMEOUT=120
```

## Security recommendation

Avoid using `admin` credentials in shell history for routine downloads. Create a dedicated read-only Nexus user for Hugging Face proxy access.

## Automation

Use `addons/hf-tuning.yaml` to apply the recommended Nexus HF proxy tuning through Ansible.

- Setup and usage guide: `docs/hf-tuning-playbook.md`
