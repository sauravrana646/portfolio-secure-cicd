# CI/CD promotion & signed release — what we built, what broke, and why

This document summarizes the work done on `portfolio-secure-cicd` to implement the promotion model and signed release pipeline (from the plan in `devops-portfolio` / `CICD_IMPROVEMENT_PLAN.md`). It covers goals, files changed, issues we hit, how the current pipeline works, and why the `decide` job exists.

---

## 1. Goal

Move from a single-branch CI demo (`main` + Trivy gates) to:

```text
feature/* → PR → dev → PR → uat → PR → main (prod)
                                      ↓
                              manual tag vX.Y.Z
                                      ↓
         quality-gate → GitHub Environment approval → GHCR
         → Infisical (cosign keys via OIDC) → cosign sign/attest
         → SLSA provenance → GitHub Release + SBOM
```

Constraints we followed:

- No separate `prod` branch (`main` is prod).
- Ask before changing GitHub settings/secrets (rulesets, env vars done in UI by you).
- Infisical placeholders first, then real identity/env values.
- Step 8 (portfolio website case study) deferred.

---

## 2. What we delivered

### Git branches

| Branch | Role |
|--------|------|
| `dev` | Integration / first promotion target |
| `uat` | Pre-prod promotion target |
| `main` | Prod (releases cut from here) |
| `demo/fail-critical` | Unchanged sales gate-fail demo |
| Feature branches | Implementation work (e.g. `feature/cicd-improvements-release`) |

### Workflows

| File | Purpose |
|------|---------|
| `.github/workflows/quality-gate.yml` | **Reusable** gate: unit tests → Trivy fs/image CRITICAL → SARIF → Syft SBOM. Called by `ci` and `release`. |
| `.github/workflows/ci.yml` | Runs on PR/push to `dev`/`uat`/`main`. Has a `decide` job (dedupe) then calls `quality-gate`. |
| `.github/workflows/promotion-guard.yml` | PR check: `uat` only from `dev`; `main` only from `uat`. |
| `.github/workflows/release.yml` | On tag `v*.*.*`: re-run quality-gate → Environment `release` → GHCR push by digest → Infisical → cosign sign/verify/attest → SLSA provenance → GitHub Release. |
| `.github/workflows/oidc-debug.yml` | Temporary debug workflow (workflow_dispatch + `environment: release`) to print OIDC `sub`/`aud`. Can be deleted. |

### Docs

| File | Purpose |
|------|---------|
| `README.md` | Promotion + release architecture, Infisical vars, badges |
| `docs/CASE_STUDY.md` | Narrative for signed supply chain + promotion |
| `policies/security-gates.md` | Per-branch gates, promotion-guard, release policy |
| `docs/BRANCH_PROTECTION_UI.md` | Ruleset / environment UI runbook |
| `docs/GITHUB_ENVIRONMENT_UI.md` | Environment `release` setup |
| `docs/CICD_PROMOTION_RETROSPECTIVE.md` | This document |

### GitHub settings (UI — not in git)

| Setting | What we configured |
|---------|-------------------|
| Ruleset `protect-dev` | Require PR; checks: `quality-gate / test`, `quality-gate / security`, GitGuardian |
| Ruleset `protect-uat` | + linear history, up-to-date, `promotion-guard / guard` |
| Ruleset `protect-main` | Same as uat + 1 approval (temporarily set to 0 when author couldn't approve own PR) |
| Tag ruleset `protect-release-tags` | Target **tags** `v*`; restrict create/update/delete |
| Environment `release` | Required reviewer; deployment tags `v*` only; env vars for Infisical |
| Environment variables | `INFISICAL_IDENTITY_ID`, `INFISICAL_ENV_SLUG=prod` |

### Infisical

| Item | Value |
|------|--------|
| Project | `devops-portfolio-x-k3-y` |
| Env for release | `prod` |
| Path | `/cosign` |
| Secrets | `cosign-private-key`, `cosign-public-key`, `cosign-key-password` |
| Identity ID | `b0d5c6ed-5178-416d-80d2-cec4ee521424` |
| Working OIDC Subject | `repo:sauravrana646@42442467/portfolio-secure-cicd@1321452770:environment:release` |
| Audience | `https://github.com/sauravrana646` |

### First successful release

- Tag: **`v0.1.0`**
- Run: https://github.com/sauravrana646/portfolio-secure-cicd/actions/runs/31281468291
- Image: `ghcr.io/sauravrana646/portfolio-secure-cicd:v0.1.0`
- Digest: `sha256:a407de4528243789ae9784099afbca03e066dcb9092f05f9ef3060b23145f1e3`
- Release: https://github.com/sauravrana646/portfolio-secure-cicd/releases/tag/v0.1.0
- Artifacts: GHCR image + `.sig` + `.att`, SLSA provenance attestation, `sbom.spdx.json` on the GitHub Release

---

## 3. How the current pipeline works

### A. Day-to-day change (feature → prod)

1. Create `feature/*` from `dev` (or current tip).
2. Open PR into **`dev`**.
   - `ci` runs (`decide` → `quality-gate`).
   - No `promotion-guard` (any source may enter `dev`).
3. Merge to `dev` when green.
4. Open PR **`dev` → `uat`**.
   - `ci` + **`promotion-guard / guard`** (must be from `dev`).
5. Merge to `uat` when green.
6. Open PR **`uat` → `main`**.
   - Same gates + typically **1 approving review**.
7. After merge to `main`, cut a release (below).

### B. Release (manual tag)

1. Maintainer (tag ruleset) pushes `vX.Y.Z` on `main`.
2. `release.yml` starts:
   - **quality-gate** (reusable) must pass again.
   - **release** job targets Environment **`release`** → waits for your approval.
3. After approval:
   - Build/push image to GHCR (`:vX.Y.Z` and `:<sha>`).
   - Canonical identity = **digest** (`@sha256:...`).
   - Fetch cosign keys from Infisical via OIDC.
   - `cosign sign` / `verify` / `attest` (SPDX SBOM) on the digest.
   - `actions/attest-build-provenance` (SLSA).
   - Create GitHub Release with notes + `sbom.spdx.json`.

### C. What each script/workflow job does

**`quality-gate` / `test`**

- Checkout, Python 3.12, `pip install -r app/requirements.txt`
- `pytest` with `PYTHONPATH=.`

**`quality-gate` / `security`**

- Trivy filesystem scan (CRITICAL fails)
- Trivy SARIF upload (fs)
- Docker Buildx build (load, no push) of hardened `Dockerfile`
- Trivy image scan (CRITICAL fails)
- Trivy SARIF upload (image)
- Syft SBOM (`spdx-json`) + upload artifact

**`promotion-guard` / `guard`**

- Reads `github.base_ref` and `github.head_ref`
- Fails unless allowed promotion edge

**`ci` / `decide`**

- See section 5 below (duplicate-check dedupe)

**`release` job**

- Lowercase image name for GHCR
- Login GHCR with `GITHUB_TOKEN`
- Build/push tags + capture digest
- Syft SBOM against digest
- Infisical secrets → env
- Cosign sign/verify/attest
- SLSA provenance
- `softprops/action-gh-release`

---

## 4. Issues we faced (and how we fixed them)

### 4.1 Tag ruleset created as a branch ruleset

**Issue:** First `protect-release-tags` targeted `refs/heads/v*` (branches), not tags.  
**Fix:** Recreate as a **tag** ruleset on `refs/tags/v*` with create/update/delete restrictions only (no PR/status-check rules).

### 4.2 Required check name mismatch (`promotion-guard / guard` vs `guard`)

**Issue:** Rulesets required `promotion-guard / guard`, but the job reported as `guard`, so `dev`→`uat` merges were blocked.  
**Fix:** Set explicit job name in the workflow:

```yaml
jobs:
  guard:
    name: promotion-guard / guard
```

### 4.3 Author cannot approve own PR (`uat` → `main`)

**Issue:** `protect-main` required 1 approval; GitHub blocks PR authors from approving their own PR. Agent/your account authored the promotion PR.  
**Fix (operational):** Temporarily set required approvals to `0`, merge, then restore to `1`.

### 4.4 Agent cannot create `v*` tags

**Issue:** Tag ruleset restricts creations; Cursor agent token got `GH013` on `git push origin v0.1.0`.  
**Fix:** You pushed the tag as maintainer from your machine.

### 4.5 Duplicate status checks on promotion PRs

**Issue:** PRs like `dev`→`uat` showed `quality-gate / test` and `quality-gate / security` **twice**.  
**Root cause:** See section 5.  
**Fix:** Added `decide` job in `ci.yml` to skip the push-path quality-gate when the SHA is already head of an open PR.

### 4.6 Squash + linear history → permanent merge conflicts between `dev`/`uat`/`main`

**Issue:** Squash-merging promotions rewrites history. Later `dev`→`uat` / `uat`→`main` PRs became `CONFLICTING` on the same files even when content was “the same intent”. GitHub’s **Resolve conflicts** UI did nothing useful for this case.  
**Why:** 3-way merge from a common old base sees both sides as having modified `ci.yml` differently.  
**Workarounds we used:**

1. Merge `uat`/`main` into `dev` with merge commits to re-establish ancestry (helped some edges).
2. For the final dedupe landing on `main`: open a **clean PR based on `main`** that copied the 3 divergent files from `uat` (`feature/apply-dedupe-onto-main` → PR #13), after temporarily removing required `promotion-guard` (because head wasn’t `uat`).

**Longer-term recommendation:** For promotion PRs between long-lived branches, prefer **merge commits** (turn off “Require linear history” on `uat`/`main`) *or* accept occasional conflict-resolution / sync PRs when using squash.

### 4.7 Commit title looked wrong on `main` CI

**Issue:** Run titled `promote: dev → uat … (#2) (#4)` while running on `main`.  
**Cause:** Squash of #4 reused the single commit message from `uat` and appended `(#4)`. Harmless; edit squash message next time to `promote: uat → main …`.

### 4.8 Infisical OIDC — “subject not allowed”

**Issues in sequence:**

1. Initial subject `repo:…/portfolio-secure-cicd:*` did not match.
2. Correct *logical* subject for Environment jobs is `…:environment:release`, not `…:ref:refs/tags/v0.1.0`.
3. Debug workflow failed first because Environment `release` only allows tags `v*` — `workflow_dispatch` on `main` was rejected before steps ran. Temporary branch allow for `main` fixed that.
4. Real JWT `sub` (from oidc-debug) was **not** the simple form. GitHub OIDC subject customization includes numeric IDs:

```text
repo:sauravrana646@42442467/portfolio-secure-cicd@1321452770:environment:release
```

Those numbers are GitHub **user ID** and **repository ID** (anti-rename collision), enabled via OIDC subject claim customization.

**Fix:** Set Infisical Subject to that exact string. Audience `https://github.com/sauravrana646` was already correct.

### 4.9 Cosign “invalid pem block”

**Issue:** After Infisical auth worked, `cosign sign` failed: `reading key: invalid pem block`.  
**Cause:** Private key material in Infisical was not valid PEM (often missing real newlines / wrong field).  
**Fix:** Re-store proper PEM for `cosign-private-key` (and matching password/public key). Re-run succeeded.

### 4.10 Permissions / API limits for the agent

Throughout, the agent could not:

- Create/update Actions variables (403)
- Create Environments / rulesets (403)
- Re-run workflows (403)
- Close some PRs via `gh` (used ManagePullRequest instead)
- Approve PRs or environment deployments

Those steps were done in the GitHub / Infisical UI by you.

---

## 5. Duplicate workflow checks — why it happened, why `decide` exists

### What you saw

On promotion PRs (`dev`→`uat`, `uat`→`main`), the Checks list showed:

- `quality-gate / test` ×2  
- `quality-gate / security` ×2  
- `decide` (later)  
- sometimes `quality-gate` **SKIPPED** (expected after the fix)

`promotion-guard` appeared once (it only listens to `pull_request`).

### Why duplicates happened

`ci.yml` is triggered by **both**:

```yaml
on:
  push:
    branches: [dev, uat, main]
  pull_request:
    branches: [dev, uat, main]
```

For a normal `feature/*` → `dev` PR:

- Only `pull_request` fires for that feature tip (`feature/*` is not in `push.branches`).
- One CI run. Fine.

For a promotion PR whose **head is a long-lived branch** (e.g. head=`dev`, base=`uat`):

1. Someone pushes/merges onto **`dev`**.
2. That creates a **`push`** event → `ci` runs for `refs/heads/dev`.
3. The open PR `dev`→`uat` also gets a **`pull_request` synchronize** event → `ci` runs again for the same commit SHA.

GitHub attaches **both** runs’ checks to that SHA on the PR → duplicate required check names.

```text
                    push to `dev`
                         │
                         ├─► ci (event=push)     ──┐
                         │                         ├─► same SHA → duplicate checks on PR
                         └─► PR sync (pull_request)─�
                         │                         ├─► same SHA → duplicate checks on PR
                         └─► PR sync (pull_request)─┘
```

### Why `decide` is needed

We still want:

- **PR runs** = merge gates (always).
- **Push runs** = post-merge branch-tip verification when there is **no** open PR for that SHA.

So `decide`:

1. If `pull_request` → `run_gate=true` (always run quality-gate).
2. If `push` → call GitHub API: “is this SHA the head of any **open** PR?”
   - Yes → `run_gate=false` (skip quality-gate; PR run covers it).
   - No → `run_gate=true` (post-merge / tip check).

```yaml
quality-gate:
  needs: decide
  if: needs.decide.outputs.run_gate == 'true'
  uses: ./.github/workflows/quality-gate.yml
```

After the fix, a promotion PR typically shows:

- One successful `quality-gate / test` + `security` (from the PR run)
- One **skipped** `quality-gate` job (from the push run) — that skip is intentional
- Possibly two `decide` jobs (one per event) — cheap; not duplicate heavy gates

### Could we have removed `push` entirely?

Yes (only `pull_request` + maybe `push` to `main`). We kept push on all three branches to match the original plan (“gates on PR and push”) while avoiding duplicate heavy scans via `decide`.

---

## 6. File-level changes (why each change)

### `.github/workflows/quality-gate.yml` (new)

Extracted shared test+security pipeline so `ci` and `release` cannot drift.

### `.github/workflows/ci.yml` (rewritten)

- Triggers limited to promotion branches.
- Calls reusable quality-gate.
- Added `decide` + `pull-requests: read` for dedupe.

### `.github/workflows/promotion-guard.yml` (new)

Enforces source-branch policy GitHub rulesets cannot express natively. Explicit `name: promotion-guard / guard` so ruleset required checks match.

### `.github/workflows/release.yml` (new)

Implements signed release on tags: Environment gate, GHCR by digest, Infisical OIDC, cosign, SLSA, GitHub Release. Uses repo/env vars for Infisical IDs (not long-lived cosign keys in GitHub).

### Docs / policies / README

Document the promotion model, ruleset UI steps, Environment `release`, Infisical mapping (`dev`/`staging`/`prod`), and security-gate policy so the demo is explainable in interviews/portfolio.

---

## 7. Environment `release` — what it adds

| Control | Effect |
|---------|--------|
| Required reviewer | Tag push alone is not enough; human approves before sign/publish |
| Deployment policy tags `v*` | Only tag refs can use this environment (blocked oidc-debug on `main` until we temporarily allowed `main`) |
| Environment variables | `INFISICAL_*` scoped to this job (narrower than repo-wide vars) |

Cosign private keys stay in **Infisical**, not GitHub Secrets.

---

## 8. Current status checklist

- [x] `dev` / `uat` / `main` promotion model + workflows  
- [x] Rulesets + tag protection  
- [x] Environment `release` + Infisical OIDC + cosign  
- [x] First release `v0.1.0` with image, sig, att, provenance, SBOM, GitHub Release  
- [x] CI dedupe (`decide`) on `main`  
- [ ] Optional cleanup: remove `oidc-debug.yml`; remove temporary `main` allow on Environment `release` if still present; confirm `protect-main` has `promotion-guard` + desired approval count again  
- [ ] Step 8: update `devops-portfolio` website case study (out of scope for this pass)  
- [ ] Consider turning off linear-history-on-squash for promotion branches to avoid future conflict pain  

---

## 9. Quick reference — verify release artifacts

```bash
IMAGE=ghcr.io/sauravrana646/portfolio-secure-cicd@sha256:a407de4528243789ae9784099afbca03e066dcb9092f05f9ef3060b23145f1e3

cosign verify --key cosign.pub "$IMAGE"
cosign verify-attestation --key cosign.pub --type spdx "$IMAGE"
gh attestation verify "oci://$IMAGE" --repo sauravrana646/portfolio-secure-cicd
```

Release page: https://github.com/sauravrana646/portfolio-secure-cicd/releases/tag/v0.1.0  
Successful run: https://github.com/sauravrana646/portfolio-secure-cicd/actions/runs/31281468291
