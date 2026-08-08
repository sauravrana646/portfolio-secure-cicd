# Branch protection & tag rules — GitHub UI steps

Apply these in the GitHub UI (Settings). Do **not** rely on the workflows alone; protection makes the checks required before merge.

Repo: `sauravrana646/portfolio-secure-cicd`

After this change lands, CI check names for the reusable workflow are typically:

- `quality-gate / test`
- `quality-gate / security`
- `promotion-guard / guard` (PRs into `uat` / `main` only)

If the exact names differ in the Checks UI after the first green run, use the names shown there.

---

## Option A — Rulesets (recommended)

**Path:** Settings → Rules → Rulesets → New branch ruleset

### 1. Ruleset: `dev`

1. **Ruleset name:** `protect-dev`
2. **Enforcement status:** Active
3. **Target branches:** Include by pattern → `dev`
4. **Rules:**
   - Restrict deletions
   - Block force pushes
   - Require a pull request before merging
     - Required approvals: `0` (or `1` if you want review on `dev`)
     - Optionally dismiss stale approvals
   - Require status checks to pass
     - Require branches to be up to date before merging: optional on `dev`
     - Add checks: `quality-gate / test`, `quality-gate / security`
5. Save.

### 2. Ruleset: `uat`

1. **Ruleset name:** `protect-uat`
2. **Enforcement status:** Active
3. **Target branches:** Include by pattern → `uat`
4. **Rules:**
   - Restrict deletions
   - Block force pushes
   - Require linear history
   - Require a pull request before merging
   - Require status checks to pass
     - Require branches to be up to date before merging: **on**
     - Add checks: `quality-gate / test`, `quality-gate / security`, `promotion-guard / guard`
5. Save.

### 3. Ruleset: `main` (prod)

1. **Ruleset name:** `protect-main`
2. **Enforcement status:** Active
3. **Target branches:** Include by pattern → `main`
4. **Rules:** same as `uat`, plus optionally:
   - Required approvals: `1`
   - Restrict who can push (bypass list empty for everyday use)
5. Save.

### 4. Tag ruleset: `v*`

1. Settings → Rules → Rulesets → **New tag ruleset**
2. **Ruleset name:** `protect-release-tags`
3. **Enforcement status:** Active
4. **Target tags:** Include by pattern → `v*`
5. **Rules:**
   - Restrict creations → allow only Maintainers / Admins (or your release role)
   - Restrict updates / deletions as desired
6. Save.

This keeps release tags deliberate (manual `git tag vX.Y.Z` by maintainers only).

---

## Option B — Classic branch protection

**Path:** Settings → Branches → Add classic branch protection rule

For each of `dev`, `uat`, `main`:

1. Branch name pattern: exact branch name
2. Enable **Require a pull request before merging**
3. Enable **Require status checks to pass before merging**
   - Add the check names listed above (`promotion-guard` only on `uat` and `main`)
   - On `uat` / `main`: enable **Require branches to be up to date before merging**
4. On `uat` / `main`: enable **Require linear history**
5. Enable **Do not allow bypassing the above settings** (unless you need an admin escape hatch)
6. Disable direct pushes implicitly by requiring PRs; leave “Allow force pushes” / “Allow deletions” off
7. Save

Classic UI has no native “source branch must be X” rule — that is why `promotion-guard` is a required check.

---

## GitHub Environment: `production` (release job)

The `release` job in `.github/workflows/release.yml` uses `environment: production`.
Create and harden it in the UI (API from this agent is 403).

**Path:** Settings → Environments → **New environment** → name: `production`

### Protection rules

1. **Required reviewers**
   - Enable
   - Add yourself (`sauravrana646`) — or a release approver
   - Leave **Prevent self-review** **off** if you are the only maintainer (otherwise you cannot approve your own tag-triggered release)
2. **Wait timer** — optional (`0` is fine; use e.g. 5–15 minutes if you want a cool-down)
3. **Deployment branches and tags**
   - Choose **Selected branches and tags**
   - Add a **tag** rule: `v*`  
     (only semver-style tags can run jobs that target this environment)
   - Do **not** allow all branches

### Environment variables (preferred over repo-wide)

On the `production` environment → **Environment variables**:

| Name | Value |
|------|--------|
| `INFISICAL_IDENTITY_ID` | `b0d5c6ed-5178-416d-80d2-cec4ee521424` |
| `INFISICAL_ENV_SLUG` | `prod` |

Jobs with `environment: production` read these via `${{ vars.* }}` (environment vars override repo vars of the same name).

Infisical project `devops-portfolio-x-k3-y`, path `/cosign`: `cosign-private-key`, `cosign-public-key`, `cosign-key-password`.  
Env mapping: Development=`dev`, uat=`staging`, Production=`prod`.  
Configure the machine identity for GitHub OIDC against this repo.

Do **not** store the cosign private key as a GitHub Actions secret if Infisical OIDC is in use.

### What this adds

| Layer | Control |
|-------|---------|
| Git promotion | rulesets + `promotion-guard` |
| Release execution | Environment required reviewer + tag `v*` only |
| Key material | Infisical OIDC (`prod` / `/cosign`) |

---

## Validation checklist (after rules are on)

1. PR `feature/*` → `dev`: `ci` runs; merge allowed when green.
2. PR `dev` → `uat`: `promotion-guard` passes; merge when green.
3. PR `feature/*` → `uat`: `promotion-guard` **fails**.
4. PR `uat` → `main`: `promotion-guard` passes.
5. PR `dev` → `main`: `promotion-guard` **fails**.
6. Maintainer pushes `v0.1.0` on `main`: `release` quality-gate runs, then `release` job waits for **production** environment approval; after approve → GHCR + cosign + GitHub Release.
