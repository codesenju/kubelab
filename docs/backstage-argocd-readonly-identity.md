# Backstage → Argo CD read-only catalog identity

Account: `backstage-catalog` (reused; no second `backstage` account is created).
Consumer: the IY Synergy Backstage Argo CD catalog provider.

**BLOCKED: pending user approval.** Nothing here is live until the PR is merged and
`addons/argocd.yaml` is re-applied with `--tags argocd`. Do not push, merge, apply or
generate a token without that approval.

## Decision: reuse, do not duplicate

The live `backstage-catalog` account is already read-only. A new `backstage` account with
the same grants would only add a second identity to rotate and revoke. The only repo change
needed is to fix drift (see below).

## Change in this PR

`addons/argocd.yaml`, `configs.cm`:

```diff
-              accounts.backstage-catalog: apiKey, login
+              accounts.backstage-catalog: apiKey
```

- The live cluster is already `apiKey` only. The repo said `apiKey, login`, so a re-run of
  `--tags argocd` would have turned UI/CLI password login on for a service account.
- `accounts.backstage-catalog.enabled: "true"` stays.
- The RBAC block is unchanged:
  - `g, backstage-catalog, role:backstage-catalog`
  - `p, role:backstage-catalog, applications, get, default/*, allow`
  - `p, role:backstage-catalog, applicationsets, get, default/*, allow`
- No `list` lines. Argo CD RBAC has no `list` verb; `get` covers API list and get.
- No sync, override, action, create, update or delete grants.

### Scope decision (not in this diff)

The role is scoped to `default/*`. `default` is the only AppProject today, so this covers
every app. Apps in a future project would be invisible to Backstage. Widening to `*/*`
is a separate, optional change (staged in task t_776f6c62). It was left out here to keep
the change a pure drift fix.

### policy.default

Not set in the repo, and empty live, so the account gets no implicit role. Keep it empty. If it
is ever set to `role:readonly` or `role:admin`, every account and token, including this
one, gains those rights. Setting it would also affect the SSO groups and `devops`.

## Blast radius

- Can read: Applications and ApplicationSets in `default`, through the Argo CD API. That
  includes live resource manifests of managed apps, **including Secret manifests**. Argo CD
  RBAC cannot exclude them. If this exposure is not acceptable, have Backstage read the
  Application custom resources through Kubernetes RBAC instead of the Argo API.
- Cannot: sync, override, run actions, create, update or delete anything, or read
  projects, repositories, clusters or certificates. This follows from `policy.csv`. Write
  verbs were not tested live with this token in this task.
- ConfigMap changes: `argocd-cm` key `accounts.backstage-catalog` goes from `apiKey, login`
  to `apiKey`. `argocd-rbac-cm` is unchanged. Live `argocd-cm` is already `apiKey`, so the
  effective change is zero.
- Restart: none expected. `argocd-server` watches both ConfigMaps. A Helm/Ansible re-apply
  only touches the ConfigMaps. Not verified on a live run.
- Existing API key (unchanged, still valid): issued 2026-11-16, no expiry.

## After approval: apply

```bash
cd ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventories/prod/hosts.ini \
  ../addons/argocd.yaml --tags argocd
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.accounts\.backstage-catalog}{"\n"}'   # apiKey
```

## After approval: rotate to an expiring token (optional)

Writes the token straight into OpenBao. Nothing is printed and no file is written.

```bash
argocd account generate-token --account backstage-catalog --expires-in <duration> \
  | bao kv put secret/agents/backstage argocd_api_token=-   # example invocation; the value never touches disk or stdout
```

Then point Backstage at `secret/agents/backstage` (key `argocd_api_token`) and check that
the catalog sync works. Remove the old token only after that:

```bash
argocd account get --account backstage-catalog          # lists token ids
argocd account delete-token --account backstage-catalog <old-token-id>
```

## Rollback and revocation

- Repo: revert the PR. This restores `apiKey, login`; do not re-apply it unless you want
  login on.
- Disable the account: set `accounts.backstage-catalog.enabled: "false"`, or remove the
  `accounts.backstage-catalog*` keys plus the `g,` and `p,` lines for `role:backstage-catalog`,
  then re-apply with `--tags argocd`.
- Revoke tokens: `argocd account delete-token --account backstage-catalog <id>`.
- Rotate or delete any copy of the token in OpenBao (`secret/agents/backstage`) and in the
  Backstage secret that consumes it.
