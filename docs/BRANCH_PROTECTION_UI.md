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

## Repo variables (release signing) — also UI

**Path:** Settings → Secrets and variables → Actions → **Variables** tab

| Name | Value |
|------|--------|
| `INFISICAL_IDENTITY_ID` | *(your Infisical machine identity ID)* |
| `INFISICAL_ENV_SLUG` | `prod` (releases); also available: `dev`, `staging` |

Infisical project `devops-portfolio-x-k3-y`, path `/cosign`: `cosign-private-key`, `cosign-public-key`, `cosign-key-password`.  
Env mapping: Development=`dev`, uat=`staging`, Production=`prod`.  
Configure the machine identity for GitHub OIDC against this repo.

Do **not** store the cosign private key as a GitHub Actions secret if Infisical OIDC is in use.

---

## Validation checklist (after rules are on)

1. PR `feature/*` → `dev`: `ci` runs; merge allowed when green.
2. PR `dev` → `uat`: `promotion-guard` passes; merge when green.
3. PR `feature/*` → `uat`: `promotion-guard` **fails**.
4. PR `uat` → `main`: `promotion-guard` passes.
5. PR `dev` → `main`: `promotion-guard` **fails**.
6. Maintainer pushes `v0.1.0` on `main`: `release` workflow runs (after Infisical variables are set).
