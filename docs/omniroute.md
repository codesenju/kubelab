# OmniRoute upgrade guide

OmniRoute runs in the `omniroute` namespace and is deployed by Argo CD from
`kustomize/omniroute/overlays/prod`. The Argo CD Application is created by the
Ansible playbook `addons/omniroute.yaml`.

Until upstream fixes its Kiro client headers, production does **not** run the
upstream image. It runs a patched image built from `docker/omniroute/Dockerfile`
and pushed to the private registry. This guide covers upgrading while the patch
is needed, and how to drop it once upstream is fixed.

## Why the patched image exists

Kiro rejects OmniRoute's Kiro provider with:

```
[Error: [400]: This version of Kiro is no longer supported. Please update to the latest version of Kiro to continue.]
```

Upstream OmniRoute (checked up to 3.8.53) hard-codes stale Kiro client
identifiers in two places:

| Path | Source file | Stale value |
|------|-------------|-------------|
| Model listing | `open-sse/services/kiroModels.ts` | `KIRO_IDE_VERSION = "0.10.32"` |
| Chat / streaming | `open-sse/config/providerHeaderProfiles.ts` | `KIRO_SDK_USER_AGENT` / `KIRO_AMZ_USER_AGENT` = `…kiro-ide/1.0.0` |

Patching only the first one is **not** enough; chat requests use the second.
The `KIRO_USER_AGENT` environment variable listed in upstream's
`docs/reference/ENVIRONMENT.md` is not read by the code, so there is no
config-only fix.

The Dockerfile rewrites both, in the compiled Next.js bundle, to the real Kiro
IDE format `KiroIDE-<kiro-version>-<machine-id>`. It locates files by content
(chunk names change between releases) and fails the build if any expected
string is missing or any stale string remains.

## How the image is wired (keep the registry host out of Git)

This repository is public. The registry host must never be committed.

- `kustomize/omniroute/overlays/prod/kustomization.yaml` references the
  **upstream** image `diegosouzapw/omniroute:<version>`.
- `addons/omniroute.yaml` overrides it on the Argo CD Application:

  ```yaml
  kustomize:
    images:
      - "IMAGE_TEMPLATE={{ registry_domain }}/kubelab/omniroute:{{ omniroute_image_tag }}"
  ```

- `registry_domain` comes from the gitignored
  `ansible/inventories/prod/group_vars/all/secrets.yaml`. The tag is the
  playbook var `omniroute_image_tag`.

Consequences:

- The image override lives in the **Application spec**, not in Git manifests.
  Changing `omniroute_image_tag` only takes effect after re-running the
  playbook with `--tags argocd`. Merging alone does nothing.
- Do not `kubectl apply -k` the overlay to change images. Argo CD runs with
  `selfHeal: true` and reverts it.

### Image tag scheme

`<omniroute-version>-kiro<kiro-ide-version>-<build>`, for example
`3.8.53-kiro1.4.178-2`. Increase `<build>` when rebuilding the same versions.
Old tags stay in the registry and are the rollback targets.

## 0. Prerequisites

Run from the repository root:

```bash
# Registry host from the gitignored inventory. Never echo it into commits, PRs or docs.
export REGISTRY="$(awk -F'"' '/^registry_domain:/{print $2}' ansible/inventories/prod/group_vars/all/secrets.yaml)"
test -n "$REGISTRY" || echo "registry_domain not found"

docker login "$REGISTRY"                  # once
kubectl config current-context            # must be the prod cluster
kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.architecture}{"\n"}{end}' | sort -u
# All nodes are amd64 today, so images are built for linux/amd64 only.
```

## 1. Pick the versions

```bash
npm view omniroute version                       # latest OmniRoute
docker manifest inspect diegosouzapw/omniroute:<version> >/dev/null && echo "image tag exists"
```

Latest Kiro IDE version: <https://kiro.dev/changelog/ide/>. Do not use the
version of a locally installed Kiro app; it may be outdated.

## 2. Check whether upstream fixed the Kiro headers

```bash
v=<omniroute-version>
tmp="$(mktemp -d)"
(cd "$tmp" && npm pack "omniroute@$v" --silent >/dev/null && tar xzf omniroute-*.tgz)
grep -n 'KIRO_IDE_VERSION =' "$tmp/package/open-sse/services/kiroModels.ts"
grep -n 'KIRO_SDK_USER_AGENT =\|KIRO_AMZ_USER_AGENT =' "$tmp/package/open-sse/config/providerHeaderProfiles.ts"
grep -rn 'process.env.KIRO_USER_AGENT' "$tmp/package/open-sse" "$tmp/package/src" || echo "KIRO_USER_AGENT still unused"
rm -rf "$tmp"
```

- Still `0.10.32` and/or `kiro-ide/1.0.0` → upstream not fixed. Go to **3A**.
- Both send a current `KiroIDE-<version>` → upstream fixed. Go to **3B**.
- File paths or constants moved → read the new `open-sse/executors/kiro.ts`
  and `open-sse/config/providerHeaderProfiles.ts` and adapt the Dockerfile.

## 3A. Upgrade while the patch is still needed

### Back up the data volume

The PVC holds the SQLite database and generated runtime secrets
(`/app/data/server.env`). Upgrades may run migrations.

```bash
kubectl -n omniroute exec deploy/omniroute -- tar czf - -C /app/data . > "omniroute-data-$(date +%F).tgz"
# Contains secrets: keep it local, outside the repo, never commit it.
```

### Build and push

```bash
v=<omniroute-version>; k=<kiro-ide-version>; tag="${v}-kiro${k}-1"
docker buildx build --platform linux/amd64 \
  --build-arg OMNIROUTE_VERSION="$v" \
  --build-arg KIRO_IDE_VERSION="$k" \
  -t "$REGISTRY/kubelab/omniroute:$tag" --push docker/omniroute
```

If the build fails with `patch 1:`/`patch 2:`/`verify:`, upstream changed
the code. Re-run step 2 and inspect the new source; do not delete the checks.

If the old Kiro version literal changed upstream, pass it explicitly:
`--build-arg OLD_KIRO_IDE_VERSION=<old>`.

### Verify the image before deploying

```bash
docker run --rm --platform linux/amd64 --entrypoint sh "$REGISTRY/kubelab/omniroute:$tag" -c '
  cd /app/.build/next
  echo "stale UA files: $(grep -rIl "kiro-ide/1.0.0" . | wc -l)"   # expect 0
  echo "patched files:  $(grep -rIl "KiroIDE-'"$k"'-" . | wc -l)"   # expect > 0
  id -u                                                            # expect 1000 (PVC fsGroup)'
```

### Update Git and deploy

1. On a branch from `main`:
   - `addons/omniroute.yaml`: set `omniroute_image_tag: <tag>`.
   - `kustomize/omniroute/overlays/prod/kustomization.yaml`: set `newTag: <v>`
     (keeps the upstream fallback aligned; overridden while the patch is in use).
   - `docker/omniroute/Dockerfile`: bump the `OMNIROUTE_VERSION` and
     `KIRO_IDE_VERSION` defaults.
2. Scan for leaks (see [Leak check](#leak-check)), open a PR, merge.
3. Apply the Application from the merged `main`:

   ```bash
   ansible-playbook addons/omniroute.yaml -i ansible/inventories/prod/hosts.ini --tags argocd
   ```

### Verify the rollout

```bash
kubectl -n omniroute rollout status deploy/omniroute --timeout=300s
kubectl -n argocd get app omniroute -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
# Show only the tag (the image string contains the registry host):
kubectl -n omniroute get deploy omniroute -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' | sed 's#^[^/]*#<registry>#'
```

Then open OmniRoute → Providers → **Kiro AI** → **Test**, send a message and
confirm a response instead of the 400 error.

### Kiro-only bump

If Kiro starts rejecting the current version again but OmniRoute itself does
not need upgrading, rebuild with the same `OMNIROUTE_VERSION` and a new
`KIRO_IDE_VERSION`, then follow the same deploy steps.

## 3B. Return to the upstream image (patch no longer needed)

1. On a branch from `main`:
   - `kustomize/omniroute/overlays/prod/kustomization.yaml`: set `newTag: <v>`.
   - `addons/omniroute.yaml`: remove the `kustomize.images` block, the
     `omniroute_image_tag` var and the `registry_domain` assertion.
   - Delete `docker/omniroute/` and this guide's patch sections.
2. Merge, then re-run the playbook with `--tags argocd`.
3. `kubernetes.core.k8s` merges into the live object, so the removed
   `images` list is **not** removed automatically. Remove it explicitly:

   ```bash
   kubectl -n argocd patch app omniroute --type json \
     -p '[{"op":"remove","path":"/spec/source/kustomize/images"}]'
   ```

4. Verify the image is now `diegosouzapw/omniroute:<v>` and run the Kiro test.

## Rollback

Set `omniroute_image_tag` back to the previous tag, re-run the playbook with
`--tags argocd`, and wait for the rollout. If a migration broke the database,
scale to 0, restore the backup into the PVC, and scale back to 1. The
Deployment uses `Recreate` because the PVC is `ReadWriteOnce`; never run two
pods at once.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Same 400 after deploying | `kubectl -n omniroute exec deploy/omniroute -- sh -c 'grep -rIl "kiro-ide/1.0.0" /app/.build/next'` must print nothing. If it is clean, upstream may send Kiro headers from another place: grep the new source for `KiroIDE`, `kiro-ide`, `User-Agent` under `open-sse/`. Check the provider **Logs** tab. |
| Kiro still rejects a clean image | The Kiro version is too old. Use the latest from the Kiro IDE changelog and rebuild. |
| Pod stays on the old image | The playbook was not re-run after changing `omniroute_image_tag`, or auto-sync is disabled: `kubectl -n argocd get app omniroute -o jsonpath='{.spec.syncPolicy.automated}'`. |
| `ImagePullBackOff` | Tag not pushed, or wrong architecture (`--platform linux/amd64`). |
| Playbook warns `unknown field "spec.source.kustomize.labels"` | Pre-existing and harmless; the installed Argo CD version ignores that field. |

## Leak check

Run before every commit, push and PR. It reads the private values from the
inventory and prints only whether they occur, never the values:

```bash
inv=ansible/inventories/prod/group_vars/all/secrets.yaml
for key in registry_domain local_dns; do
  awk -F'"' -v k="^$key:" '$0 ~ k {print $2}' "$inv" | while read -r val; do
    [ -z "$val" ] && continue
    base="$(printf '%s' "$val" | awk -F. '{print $(NF-1)"."$NF}')"   # also catch the bare domain
    for pat in "$val" "$base"; do
      if git diff --cached | grep -qiF "$pat" || git log origin/main..HEAD --format=%B | grep -qiF "$pat"; then
        echo "LEAK: (part of) $key found in staged diff or commit messages"
      fi
    done
  done
done | sort -u
```

Also check the PR title and body before submitting.

## Instructions for AI agents

Follow these rules when asked to upgrade, patch or debug OmniRoute in this repository.

1. **Never commit private data.** This repo is public. Do not put the registry
   host, any personal domain, secrets, tokens, API keys or the contents of
   `/app/data` into files, commit messages, branch names, PR titles/bodies,
   comments or issues. Refer to hosts as `{{ registry_domain }}`,
   `{{ local_dns }}` or `<registry>`. Run the [Leak check](#leak-check) before
   every commit and PR. Mask the registry when printing image names
   (`sed 's#^[^/]*#<registry>#'`).
2. **Do not hard-code the registry in the overlay.** The image override
   belongs only in the Argo CD Application in `addons/omniroute.yaml`, fed
   from inventory, following the `addons/media-stack.yaml` pattern.
3. **Check upstream first** (step 2). If upstream is fixed, prefer 3B over
   rebuilding the patch.
4. **Confirm with the user before:** pushing an image, changing versions,
   running the playbook, disabling Argo CD auto-sync, pushing to `main`, or
   deleting branches. Prefer a branch plus PR; never push directly to `main`
   unless told to.
5. **Do not weaken the Dockerfile checks.** If a `patch`/`verify` step fails,
   investigate the new upstream source and adapt the patch.
6. **Build for `linux/amd64`** unless the node architecture check shows otherwise.
7. **Deploy through the playbook** (`--tags argocd`), not `kubectl apply`.
   If auto-sync is disabled temporarily for testing, restore it
   (`kubectl -n argocd patch app omniroute --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'`)
   or re-run the playbook, and tell the user.
8. **Back up `/app/data` before upgrading** and keep the archive outside the repo.
9. **Verify end to end.** A successful build or rollout is not enough: check
   the bundle strings in the running pod and ask the user to run the Kiro AI
   provider test in the OmniRoute UI, since that needs their logged-in session.
10. **Do not touch unrelated uncommitted work.** Use a separate `git worktree`
    from `origin/main` for OmniRoute changes, and stage files by name.
