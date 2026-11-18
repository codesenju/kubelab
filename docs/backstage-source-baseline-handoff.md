# Backstage source baseline handoff (t_397b4da5)

Date: 2026-11-18. Scope: reconcile the Backstage application source, its worktrees and the
claims of earlier tasks against what is actually deployed. Nothing was reset, cleaned,
force-pushed or deployed. Hostnames, IPs and credentials are deliberately omitted.

## Baseline

| Item | Value |
| --- | --- |
| Application repository | `/root/workspace/backstage-iy-synergy` (local only, no git remote configured) |
| Reconciled branch | `reconcile/backstage-baseline-t_397b4da5` |
| Commit | `da2ec0b795fc25f0cfb3aff3f4bfe0d9d689c31f` |
| Parents | `b25e806` (latest app lineage) and `2615dca` (Argo provider commit, previously outside the lineage) |
| Archived stale draft | `snapshot/canonical-uncommitted-t_397b4da5` at `aabdbed` (archival only, do not deploy) |
| Feature-work worktree | `/root/workspace/backstage-iy-synergy/.worktrees/t_397b4da5` (clean, deps installed) |

The merge uses the `ours` strategy on purpose, so the tree is byte-identical to `b25e806`.
`2615dca` is a strict subset of what `6597847` already carries: the same Argo provider
without the project, target-revision, reconciled-at and owner fields, the status state
or the TechDocs links. Its `auth.tsx` is replaced by `signInModule.tsx`. Nothing was dropped.
`wt/t_ad89ea25` still points at `2615dca`.

`b25e806` contains, in order: `7b79675` OIDC sign-in, email resolver and catalog users;
`6597847` Argo applications page, storage inventory and TechDocs; `b25e806` homelab docs.

## Preserved changes

- OIDC-only sign-in: the guest backend module and the guest provider config are gone.
  The only auth backend module is `plugin-auth-backend-module-oidc-provider`.
  The only provider is `auth.providers.oidc.production`.
- Sign-in resolver: `emailMatchingUserEntityProfileEmail`. It fails closed unless a catalog
  `User` with a matching profile email exists, so catalog-user restriction holds.
- Catalog users come from `examples/org.yaml` (two operator identities plus the legacy
  `guest` user and `guests` group, which are catalog data only, not a sign-in path).
  Group membership is enforced in Authentik, not in Backstage config. This was not
  re-verified here.
- Argo CD catalog provider with GET-only reads, a full mutation only after both lists validate,
  and owner and TechDocs link options.
- Platform plugin: storage inventory backend and UI, Argo status route, responsive nav
  and homepage, TechDocs build scripts.

## Discrepancies: claimed vs actual

1. **t_185a9366** is blocked and its body says the OIDC and catalog fixes are
   uncommitted. They are committed as `7b79675` and the worktree is clean. The
   uncommitted changes were in the canonical checkout instead: an older draft that used
   `prompt: login`, had no `callbackUrl`, had no `agents` user and added an extra `jazziro` user to
   `examples/entities.yaml`. It is superseded by `7b79675` and archived, not merged.
2. **t_eca5b7b1** (and t_ad89ea25, t_be3b4410) reported the provider as uncommitted and
   disabled by default. It is committed as `2615dca` on a divergent line, and the
   shipping lineage carries a later version with `enabled: true`. Live
   status: the running image's `app-config.production.yaml` has no `argocd:` block. The live
   image therefore predates the Argo provider and the platform plugin, and the catalog is not
   being synced from Argo.
3. **Argo URL and token wiring is broken in the live Deployment.** `ARGOCD_API_URL` points at
   port 8083, but the `argocd-server` Service exposes 80 and 443 (container port 8080).
   `ARGOCD_API_TOKEN` is read from the `backstage-postgres-secrets` Secret with `optional: true`,
   and the key exists. The `backstage-catalog` Argo account exists in `argocd-cm`. Its
   effective permissions were not verified.
4. **t_2c14abc9** (storage inventory) reports done, but its Python service,
   manifests and tests exist only as uncommitted files in its worktree. None of it is on
   `origin/main`, and no inventory Deployment exists live. The in-app storage inventory in
   `6597847` is a separate implementation that is also not in the live image.
5. **t_ec836316** (TechDocs) reports done, but `docs/techdocs/**` and `mkdocs.yml` are uncommitted in
   its worktree and absent from `origin/main`. The app repo has its own generated
   docs from `6597847`. TechDocs serving is not verified live.
6. **t_22033d48** is in triage. Its comments say live Backstage is `Degraded`, 0/1, image
   not found, no route and Guest sign-in broken. That is stale. The Argo app is now
   `Synced/Healthy`, the Deployment is 1/1, an HTTPRoute exists and OIDC sign-in is
   deployed. Logs show a completed OIDC callback that issued a token for a catalog user.
   An end-to-end sign-in by the `agents` test identity was never verified, and t_185a9366 says
   the headless browser could not complete the popup.
7. **Argo Application spec has a stale image override.** It overrides
   `ghcr.io/codesenju/backstage` to a different digest, but the manifests use the
   placeholder `IMAGE_NAME`, so the override matches nothing and is inert. The
   overlay on `main` carries the real pin. Remove the override from the Application source of truth.
8. **A tracked `.env` exists at `kustomize/backstage/overlays/prod/.env` on `origin/main`** (since
   the initial commit, two keys: username and password). The values were not printed.
   If they are real, treat them as exposed and rotate them. Moving them to the secret store is
   recommended.
9. **The app source contains private LAN hostnames and operator email addresses**
   (`app-config.production.yaml`, `examples/org.yaml`, `Sidebar.tsx`). The app repo has no remote, so
   nothing is published. Before any push to a public remote, parameterise these or use a private repo.
   The KubeLab pre-commit hook will block them.

## Currently deployed

- Argo Application `backstage`: `Synced`, `Healthy`, at KubeLab revision `53032bb`.
- Image reference (Deployment and Pod `imageID` agree):
  `kubelab/backstage@sha256:fe8ca0553a4e6819129068fe8b9cd6010a5359f4583cffc33decd92fcec277ad`
  in the private registry. The overlay pins this digest.
- Source commit behind that digest: `7b79675` per its commit message ("deployed as oidc-catalog-20261118").
  This is unverified, because there is no digest-to-commit provenance and the image labels were not inspected.
- No new image was built or pushed.

## Verification (worktree `t_397b4da5`, tree identical to `b25e806`)

| Check | Result |
| --- | --- |
| `yarn install --immutable` | passed |
| `tsc --noEmit` | exit 0 |
| `backstage-cli repo test` | 4 suites, 23 tests passed, exit 0 |
| `backstage-cli repo build --all` | exit 0 |
| Guest/local sign-in grep over app, backend, config | no matches |
| Secret and IP scan of tracked files | no secrets or public IPs; private hostnames and emails flagged in item 9 |

Not run: lint, prettier, Playwright e2e, an image build, a real browser login.

## Backups (outside any repo, mode 700, no secrets)

`/root/workspace/backups/backstage-reconcile-t_397b4da5/` holds:

- `all-refs.bundle`: every ref of the app repo before the reconcile branches were added.
- `canonical-uncommitted.patch` and `signInModule.tsx`: the stale draft.
- Uncommitted patches for t_09ab8d16 and t_6e95ff1e.
- Tarballs of the uncommitted files in the KubeLab worktrees for t_22033d48, t_2c14abc9 and t_ec836316
  (tracked `.env` files excluded).

## Remaining before feature work

- The canonical checkout still has the stale draft uncommitted, on `feat/iy-synergy-platform` at `0258a9c`.
  I did not touch it. Start feature work from the reconcile branch worktree. After checking the archive,
  the operator can discard the draft and fast-forward that branch.
- The uncommitted KubeLab files for t_2c14abc9 and t_ec836316 are not on any branch. They are backed up. The
  owner should decide to commit, discard or supersede them.
- t_09ab8d16 and t_6e95ff1e hold staged nav changes that diverge from `b25e806`. They are backed up as patches and not merged.
- A new image build is still needed to ship `6597847` and later. Fix the Argo URL port, make the token
  Secret reference explicit and verify `backstage-catalog` is read-only before activating.
