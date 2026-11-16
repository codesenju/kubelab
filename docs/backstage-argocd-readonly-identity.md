# Backstage → Argo CD read-only catalog identity

Prepared 2026-11-16 (recovery-ops) for the IY Synergy Backstage catalog synchronization
workstream (Hermes board `IY Synergy Platform V2`, tasks `t_b418805f` / `t_0f22360d`).

**Status: PREPARED — awaiting human approval before applying.** Nothing in this branch is
live until the PR is merged and the playbooks run.

## What this branch changes

1. `addons/argocd.yaml` — Argo CD RBAC (helm `configs`):
   - New role `role:backstage-catalog`:
     - `p, role:backstage-catalog, applications, get, default/*, allow`
     - `p, role:backstage-catalog, applicationsets, get, default/*, allow`
   - New account binding: `g, backstage-catalog, role:backstage-catalog`
   - `argocd-cm` account enablement: `accounts.backstage-catalog: apiKey, login` + `enabled: "true"`
   - **Granted:** `get` on `applications` and `applicationsets` in project `default` (covers
     Argo CD API list+get). **Not granted:** `sync`, `update`, `delete`, admin, projects,
     repositories, or any other resource.
   - The existing `devops` account is **unchanged** and must **not** be reused for the
     Backstage provider (it carries `applications,sync`).

2. `kustomize/backstage/base/backstage.yaml` — deployment env:
   - `ARGOCD_API_URL` = `http://argocd-server.argocd.svc.cluster.local:8083` (in-cluster API)
   - `ARGOCD_API_TOKEN` from secret `backstage-postgres-secrets` key `ARGOCD_API_TOKEN`
     (`optional: true` — the app boots before the token exists)
   - The token enters via the existing `secretGenerator`/`.env` pattern
     (`kustomize/backstage/overlays/prod/.env`), same as the Postgres credentials.

## Approval + apply procedure (human)

1. Review/merge this PR.
2. Apply the Argo CD change (existing Ansible path used for `addons/argocd.yaml`, or
   `helm upgrade argocd ...` with the same values). Verify:
   `argocd admin whoami` / `kubectl -n argocd get cm argocd-cm -o yaml | grep backstage`
3. Generate the API token for the new account:
   `argocd account token generate backstage-catalog`
4. Store the token:
   - preferred: OpenBao (e.g. `bao kv put secret/data/backstage argocd_api_token=<token>`),
   - then set `ARGOCD_API_TOKEN=<token>` in `kustomize/backstage/overlays/prod/.env`
     (the tracked `.env` file — long-term, move all overlay secrets to OpenBao-injected
     values; flagged as a hygiene item, not part of this change).
5. Argo CD syncs the backstage deployment; verify from inside the cluster:
   `curl -s -H "Authorization: Bearer <token>" $ARGOCD_API_URL/api/v1/apps | head`
6. Unblock Hermes task `t_b418805f` (implementation) once the token round-trip is verified.

## Rollback

- Remove the two `p,` / `g,` policy lines and the two `accounts.backstage-catalog*` cm keys;
  `argocd account delete backstage-catalog`; unset `ARGOCD_API_TOKEN` in `.env`.
