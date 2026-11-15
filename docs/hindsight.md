# Hindsight memory for Obito

Hindsight provides Obito with long-term, semantic memory. The Ansible add-on
creates its database and secrets, registers the pinned official Hindsight Helm
chart with Argo CD, installs the Hermes Hindsight plugin on LXC 106, and
activates it for Obito.

## Architecture

- Hindsight chart: `ghcr.io/vectorize-io/charts/hindsight`, pinned at `1.2.1`.
- PostgreSQL: dedicated CNPG 1.29 cluster, PostgreSQL 18 with `pgvector` 0.8.7.
- Backups: CNPG Barman Cloud plugin to `s3://cnpg/new-backups/hindsight-postgres`;
  daily at 02:00 with 14-day retention.
- The Control Plane/UI and API are exposed through the private Gateway at
  `https://hindsight.<local_dns>`. `/` routes to the UI; `/v1` and `/mcp`
  route to the API.
- LLM extraction uses the configured OmniRoute OpenAI-compatible endpoint and
  model `github/gpt-6-luna`. Hindsight handles embeddings and reranking locally.

Hindsight API auth is enabled with its built-in bearer-key tenant extension.
The route is private, but network location is not an authorization boundary;
the API key is still required. The API key is shared, so it does not isolate
banks by client. Do not issue it to untrusted clients or store secrets in memory.

## OpenBao and Kubernetes secrets

The playbook reads these values from `secret/agents/hindsight`:

- `hindsight_api_key` — Hindsight API bearer key used by Obito.
- `hindsight_db_password` — CNPG bootstrap/runtime password.
- `omniroute_api_key` — LLM credential for Hindsight extraction.
- `hindsight_cp_access_key` — separate Control Plane login key.

RustFS backup credentials come from the locally ignored production Ansible
inventory. Secret-reading and Kubernetes Secret tasks use `no_log`; never print
secret values or put them in Helm parameters or Git. Chart 1.2.1 injects the
shared runtime Secret into both API and Control Plane pods, so the Control Plane
also receives the database and LLM credentials; restrict pod and Secret access.

## Access the UI

Open `https://hindsight.<local_dns>` on the private network and sign in with the
Control Plane access key stored in OpenBao. Retrieve it locally when needed:

```sh
bao kv get -field=hindsight_cp_access_key secret/agents/hindsight
```

The UI login key is distinct from the API bearer key. Anyone with UI access can
read and manage memory banks; share it only with trusted users.

## Deploy

Run from `ansible/` with a valid OpenBao login and the production inventory:

```sh
export ANSIBLE_CONFIG=ansible.cfg
ansible-playbook -i inventories/prod/hosts.ini ../addons/hindsight.yaml \
  --vault-password-file ~/vault-password.txt
```

The playbook creates the CNPG cluster, `vector` extension, RustFS object store,
daily backup, Hindsight Argo application and private Gateway route. It waits
for the database and API to become healthy before configuring Obito.

## Obito integration

The playbook installs the catalog `hindsight` Hermes memory provider, sets
`memory.provider: hindsight`, and configures local-external mode with bank
`obito`, automatic retain/recall, and hybrid memory. The API key is materialized
into the root-only Hermes `.env`; `config.json` contains no credential. The
bank is created on its first write. Hermes' built-in `MEMORY.md` and `USER.md`
remain enabled alongside Hindsight.

The gateway restarts at the end of the playbook so it loads the new provider;
this causes a brief interruption to Obito's messaging connection. Existing
sessions may need `/new` to receive the updated memory snapshot.

## Verification

On 2026-11-14, Hermes reported Hindsight active with built-in memory enabled,
and authenticated retain/recall succeeded in a separate integration-test bank.
Recall also succeeded from Obito over HTTPS. An unauthenticated request returned
401. A complete Hermes conversation-cycle test remains outstanding.

The backup schedule exists, but a completed backup has not been verified. The
Kubernetes API became intermittently unavailable during verification; inspect
backup status and cluster health before relying on recovery.

```sh
kubectl get cluster,objectstore,scheduledbackup,backup -n hindsight
kubectl get application hindsight -n argocd
kubectl get httproute hindsight -n hindsight
kubectl logs -n hindsight deploy/hindsight-api
```

On Obito:

```sh
hermes memory status
```

Use a harmless test conversation to verify recall and retain. Hindsight sends
retained turns to the configured LLM provider for extraction.

## Recovery and upgrades

Restore the CNPG cluster from its Barman Cloud backup to a separate recovery
cluster first. Validate extension availability, API health, and recall before
cutover; never test restores over the live memory database.

Upgrade by changing the pinned chart and image versions together in
`addons/hindsight.yaml`, reviewing upstream migration notes, and running
Ansible. Keep the PostgreSQL major version stable unless performing a separate
database upgrade.
