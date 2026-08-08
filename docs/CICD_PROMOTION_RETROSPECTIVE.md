# CI/CD promotion & signed release — deep dive

This document explains **what we built**, **why each file/line exists**, **every issue we hit**, and two topics in extra detail:

1. **Duplicate CI checks** on promotion PRs (and the `decide` job)
2. **Squash merge + linear history** conflicts between `dev` / `uat` / `main`

Read top-to-bottom, or jump:

- [Pipeline overview](#1-pipeline-overview)
- [File-by-file / line-by-line](#2-file-by-file--line-by-line)
- [Duplicate runs (detailed)](#3-duplicate-runs--detailed)
- [Squash merge conflicts (detailed)](#4-squash-merge-conflicts--detailed)
- [Issues log](#5-issues-we-faced)
- [Release v0.1.0 outcome](#6-release-v010-outcome)
- [Cleanup / next](#7-cleanup--next)

---

## 1. Pipeline overview

```text
feature/* ──PR──► dev ──PR (guard)──► uat ──PR (guard)──► main
                                                              │
                                                         tag vX.Y.Z
                                                              ▼
                    quality-gate → Environment `release` approval
                         → GHCR (tag + digest)
                         → Infisical OIDC → cosign sign/attest
                         → SLSA provenance → GitHub Release + SBOM
```

| Stage | Trigger | Workflows | Required idea |
|-------|---------|-----------|----------------|
| feature → `dev` | PR into `dev` | `ci` (`decide` + `quality-gate`) | Any source OK |
| `dev` → `uat` | PR into `uat` | `ci` + `promotion-guard` | Head **must** be `dev` |
| `uat` → `main` | PR into `main` | `ci` + `promotion-guard` (+ review) | Head **must** be `uat` |
| Release | Push tag `v*.*.*` | `release` (calls `quality-gate` first) | Human approves Environment `release` |

There is **no** separate `prod` branch. **`main` is prod.**

---

## 2. File-by-file / line-by-line

### 2.1 `.github/workflows/quality-gate.yml`

**Why it exists:** One shared definition of “is this commit shippable?” used by both everyday CI and the release pipeline, so gates cannot drift.

| Lines | What | Why |
|------:|------|-----|
| 1–2 | Comment | Documents callers (`ci`, `release`) |
| 3 | `name: quality-gate` | Workflow display name |
| 5–6 | `on: workflow_call` | **Only** reusable — never triggers by itself |
| 8–11 | `permissions` | Read code; write SARIF to code scanning; read actions (Trivy/cache helpers) |
| 13–14 | `IMAGE_NAME` | Local tag for the CI-built image (`portfolio-secure-cicd:ci`) |
| 17–27 | Job `test` | Fast fail before expensive Docker/Trivy |
| 20 | `actions/checkout` | Get repo at the SHA under test |
| 21–23 | `setup-python` 3.12.8 | Match app runtime |
| 24–25 | `pip install -r app/requirements.txt` | App + pytest deps |
| 26–27 | `PYTHONPATH=. pytest -q` | Unit tests (e.g. `/healthz`) |
| 29–31 | Job `security` `needs: test` | Do not scan if tests failed |
| 36–46 | Trivy **fs gate** | CRITICAL vulns in filesystem → **fail** (`exit-code: 1`) |
| 42–44 | `ignore-unfixed` + `scanners: vuln` | Only real vulns; skip secret heuristics noise |
| 45–46 | `.trivyignore` + `trivy.yaml` | Documented risk acceptances / config |
| 48–61 | Trivy FS SARIF | Report CRITICAL+HIGH for GitHub Security UI even if gate already failed (`if: always()`) |
| 63–69 | Upload SARIF | `continue-on-error` so missing Code Scanning setup does not hard-fail |
| 71–83 | Buildx + build | Build hardened `Dockerfile`, **do not push** (`push: false`, `load: true`) |
| 85–94 | Trivy **image gate** | CRITICAL in the built image → **fail** |
| 96–116 | Image SARIF + upload | Same pattern as FS |
| 118–129 | Syft SBOM + artifact | SPDX JSON kept as CI artifact (release regenerates against the **pushed digest**) |

**Check names on a PR:** `quality-gate / test`, `quality-gate / security`  
(parent job name from caller + nested job name)

---

### 2.2 `.github/workflows/ci.yml`

**Why it exists:** Entry point for promotion-branch quality gates, plus logic to avoid double-running that gate.

| Lines | What | Why |
|------:|------|-----|
| 1 | `name: ci` | Badge / Actions list name |
| 3–7 | `on.push` + `on.pull_request` to `dev`/`uat`/`main` | Gates on every promotion branch, for PRs **and** post-merge pushes |
| 9–13 | Permissions | Includes `pull-requests: read` so `decide` can query open PRs for a SHA |
| 16–18 | Comment | Explains duplicate-check problem |
| 19–50 | Job `decide` | Outputs `run_gate=true\|false` |
| 21–22 | `outputs.run_gate` | Consumed by next job’s `if:` |
| 26–30 | Env: token, event, sha, repo | Inputs to the shell decision |
| 33–37 | If event is `pull_request` → always run gate | PR is the merge gate of record |
| 39–42 | `gh api .../commits/{SHA}/pulls` | “Is this SHA head of an open PR?” |
| 44–50 | If open PRs > 0 on push → skip gate; else run | See [§3](#3-duplicate-runs--detailed) |
| 52–55 | Job `quality-gate` | Calls reusable workflow only when `run_gate == true` |
| 53 | `needs: decide` | Wait for decision |
| 54 | `if: ... == 'true'` | Skip nested heavy jobs when duplicate |
| 55 | `uses: ./.github/workflows/quality-gate.yml` | Shared implementation |

---

### 2.3 `.github/workflows/promotion-guard.yml`

**Why it exists:** GitHub rulesets can require checks and PRs, but **cannot** say “only branch X may merge into Y”. This workflow is that rule.

| Lines | What | Why |
|------:|------|-----|
| 1–2 | Comment | Documents intent |
| 3 | `name: promotion-guard` | Workflow name |
| 5–7 | `pull_request` → bases `uat`, `main` | Only promotion targets need source enforcement (`dev` accepts any feature) |
| 9–10 | `contents: read` | Minimal perms (no checkout even needed) |
| 13–15 | Job id `guard` + **`name: promotion-guard / guard`** | Rulesets require the check string `promotion-guard / guard`. Without `name:`, GitHub showed only `guard` and merges stayed blocked |
| 19–21 | `BASE_REF` / `HEAD_REF` | Target branch vs source branch of the PR |
| 26–34 | If base is `uat`, head must be `dev` | Fail with clear error otherwise |
| 36–44 | If base is `main`, head must be `uat` | Same for prod |
| 46–47 | Unexpected base → fail | Safety net |

**Examples**

| PR | Result |
|----|--------|
| `dev` → `uat` | Pass |
| `feature/x` → `uat` | Fail |
| `uat` → `main` | Pass |
| `dev` → `main` | Fail |

---

### 2.4 `.github/workflows/release.yml`

**Why it exists:** Produce a **verifiable** release artifact (digest-signed image + SBOM attestation + provenance + GitHub Release) only when a human intentionally tags.

| Lines | What | Why |
|------:|------|-----|
| 1–2 | Comment | Manual semver from `main` |
| 3 | `name: release` | Workflow name / badge |
| 5–8 | `on.push.tags: v*.*.*` | Only version tags (not every commit) |
| 10–16 | Permissions | OIDC (`id-token`), release notes (`contents`), GHCR (`packages`), SLSA (`attestations`), SARIF from nested gate |
| 18–19 | `REGISTRY: ghcr.io` | Constant |
| 22–23 | Job `quality-gate` via reusable | Never sign a tag that fails tests/Trivy |
| 25–35 | Job `release` | Needs gate; exposes digest outputs |
| 30–32 | `environment: release` | Required reviewer + tag policy; Infisical vars live here; **changes OIDC `sub` to `environment:release`** |
| 37–39 | Checkout `fetch-depth: 0` | Full history for release notes |
| 41–42 | Lowercase `IMAGE_NAME` | GHCR requires lowercase image names |
| 44–49 | `docker/login-action` | Push with `GITHUB_TOKEN` |
| 51–65 | Build **and push** | Tags `:vX.Y.Z` and `:<fullsha>`; captures `digest` |
| 67–75 | `IMAGE_REF=registry/name@sha256:...` | **Sign the digest, never a mutable tag alone** |
| 77–82 | Syft SBOM on pushed digest | Predicate for cosign attest |
| 84–85 | Install cosign | CLI for sign/verify/attest |
| 93–101 | Infisical OIDC fetch `/cosign` | No long-lived cosign private key in GitHub Secrets |
| 97–99 | `identity-id` / `project-slug` / `env-slug` | Project `devops-portfolio-x-k3-y`, env from var (we use `prod`) |
| 103–107 | `cosign sign` with password from env | Signs digest |
| 109–112 | `cosign verify` | Fail release if signature does not verify |
| 114–119 | `cosign attest --type spdx` | Attach SBOM attestation to digest |
| 121–126 | SLSA provenance action | GitHub-native attestation complementary to cosign |
| 128–168 | GitHub Release body | Documents tag↔digest mapping + verify commands; attaches `sbom.spdx.json` |

---

### 2.5 Docs / policy files (what they mean)

| File | Role |
|------|------|
| `README.md` | Public story: mermaid promotion flow, release prereqs, stack table, badges |
| `docs/CASE_STUDY.md` | Interview/portfolio narrative (problem → approach → signed release) |
| `policies/security-gates.md` | Normative policy tables (what fails CI, promotion rules, release gate) |
| `docs/BRANCH_PROTECTION_UI.md` | Click-path for rulesets + tag protection + Infisical vars |
| `docs/GITHUB_ENVIRONMENT_UI.md` | Click-path for Environment `release` |
| `docs/CICD_PROMOTION_RETROSPECTIVE.md` | This deep dive |
| `.github/workflows/oidc-debug.yml` | Temporary debugger (safe to delete after Infisical is stable) |

---

## 3. Duplicate runs — detailed

### 3.1 The trigger configuration

```yaml
# ci.yml
on:
  push:
    branches: [dev, uat, main]
  pull_request:
    branches: [dev, uat, main]
```

Important GitHub semantics:

- `pull_request.branches` filters the **base** (target) of the PR.
- `push.branches` filters the branch that received the commit.

### 3.2 Case A — feature PR (no duplicate)

```text
feature/foo ──PR──► dev
```

| Event | Fires? | Why |
|-------|--------|-----|
| `pull_request` (base=`dev`) | Yes | Normal PR checks |
| `push` to `feature/foo` | **No** for `ci.yml` | `feature/foo` is not in `push.branches` |

**Result:** one `ci` run → one `quality-gate / test` + one `quality-gate / security`.

### 3.3 Case B — promotion PR (duplicate before `decide`)

```text
Open PR:  dev ──► uat
Then:     merge a hotfix into `dev` (or any push to `dev`)
```

Timeline with real shapes we saw:

```text
T0  PR #2 open: head=dev, base=uat, head SHA = AAA
T1  Someone merges commit onto `dev` → new tip SHA = BBB

T1a push event
    ref = refs/heads/dev
    sha = BBB
    → workflow "ci" run #P  (event_name=push)

T1b pull_request synchronize
    PR #2 updated to BBB
    → workflow "ci" run #Q  (event_name=pull_request)

Both runs attach checks to commit BBB.
PR Checks tab shows:

  quality-gate / test       (from run #P)
  quality-gate / test       (from run #Q)   ← duplicate
  quality-gate / security   (from run #P)
  quality-gate / security   (from run #Q)   ← duplicate
```

Same pattern for `uat` → `main` when `uat` is the PR head and also in `push.branches`.

### 3.4 Why GitHub shows both

Status checks are keyed primarily by **(commit SHA, check name)**.  
Two workflow runs on the same SHA with the same job names → two rows with the same label.

Rulesets only need **one** green instance of a required context, but the UI looks broken/confusing and burns 2× Actions minutes (Docker+Trivy twice).

### 3.5 What `decide` does (with example outputs)

**On `pull_request` (run #Q):**

```text
EVENT_NAME=pull_request
→ run_gate=true
→ quality-gate runs   ✅ (merge gate of record)
```

**On `push` while PR open (run #P):**

```text
EVENT_NAME=push
SHA=BBB
gh api repos/.../commits/BBB/pulls  → finds open PR #2
→ run_gate=false
→ quality-gate job SKIPPED   ✅ intentional
```

**On `push` after PR merged (post-merge tip):**

```text
EVENT_NAME=push
SHA=CCC  (squash merge commit on uat)
open PRs for CCC → 0
→ run_gate=true
→ quality-gate runs once on the branch tip
```

### 3.6 What you should see after the fix

On a promotion PR:

| Check | Count | Notes |
|-------|------:|-------|
| `decide` | 1–2 | Cheap; one per event is OK |
| `quality-gate / test` | **1** success | From PR run |
| `quality-gate / security` | **1** success | From PR run |
| `quality-gate` (parent) | 0–1 **skipped** | From push run — expected |
| `promotion-guard / guard` | 1 | PR-only workflow |

### 3.7 Alternatives we considered

| Approach | Pros | Cons |
|----------|------|------|
| Remove `push` triggers entirely | No duplicates | No post-merge tip verification on `dev`/`uat` |
| `push` only on `main` | Simpler | Weaker tip checks on `dev`/`uat` |
| Concurrency cancel by SHA | Less YAML | Cancelled required checks can flake merges |
| **`decide` skip (chosen)** | Keeps plan’s push+PR intent | Extra tiny job; skipped row still visible |

---

## 4. Squash merge conflicts — detailed

### 4.1 What “Squash and merge” does

Suppose `dev` has commits:

```text
main/uat base:  A
dev:            A — B — C — D
```

**Squash and merge** into `uat` creates **one new commit** `S1` on `uat` whose **tree** equals `D`, but whose **parent** is only `A` (or previous `uat` tip) — **not** `B/C/D`:

```text
uat after squash:  A — S1
                   (S1 has same files as D, but history does not contain B,C,D)
dev still:         A — B — C — D
```

`S1` and `D` are **different commits** with (often) the **same file contents**.

### 4.2 Why the next promotion conflicts

Later you add commit `E` on `dev` (e.g. CI dedupe):

```text
dev:  A — B — C — D — E
uat:  A — S1
```

Open PR `dev` → `uat`. GitHub computes a **3-way merge**:

```text
merge-base = A
ours       = uat tip S1   (ci.yml version from first promotion squash)
theirs     = dev tip E    (ci.yml version with decide job)
```

Both `S1` and `E` changed `ci.yml` relative to `A` → Git marks **conflict**, even if you “know” `E` should win.

That is exactly what we saw on PRs #6, #9, #12:

```text
changed in both
  base   ... .github/workflows/ci.yml   (old, from A)
  our    ... .github/workflows/ci.yml   (uat squash S1 — no decide)
  their  ... .github/workflows/ci.yml   (dev — with decide)
```

### 4.3 Why “Resolve conflicts” UI sometimes does nothing

Common with rulesets + busy PRs + large histories:

- UI button no-ops or never opens the editor
- Even when it works, you must commit the resolution **onto the head branch** (`uat`), which is protected

So we often could not resolve in-browser.

### 4.4 Why merging `main` into `dev` helps some edges but not squash→main

If you create a **merge commit** on `dev` that has `uat` (or `main`) as a parent:

```text
dev:  ... — M   (M parents: previous-dev + uat-tip)
```

Then `dev`→`uat` can become a clean fast-forward/simple merge **until the next squash onto `uat`**, which again creates a new tip `S2` that is **not** an ancestor of `dev`.

Squash onto `main` has the same effect vs `uat`.

### 4.5 The repair we used for `main` (PR #13)

Because `uat`→`main` stayed `CONFLICTING` and the conflict UI failed:

1. Branched **from `main`** (same parent history as target).
2. Copied the 3 divergent files from `uat` (`ci.yml`, `README.md`, `policies/security-gates.md`).
3. Opened a normal PR into `main` — **clean merge** (no 3-way conflict).
4. Temporarily removed required check `promotion-guard / guard` (head was not `uat`).
5. Squash-merged #13.

That lands the **tree** we wanted without fighting squash ancestry.

### 4.6 Concrete example with fake SHAs

```text
Day 1
  main/dev/uat all at A (ci.yml = OLD)

Day 2 — land promotion workflows on dev (commits B,C,D), squash to uat as S1
  dev:  A-B-C-D     ci.yml=NEW1
  uat:  A-S1        ci.yml=NEW1  (same bytes as D, different commit)
  main: A           ci.yml=OLD

Day 3 — squash uat→main as S2
  main: A-S2        ci.yml=NEW1

Day 4 — add decide job on dev as E
  dev:  A-B-C-D-E   ci.yml=NEW2 (has decide)
  uat:  A-S1        ci.yml=NEW1
  PR dev→uat: merge-base A, both sides changed ci.yml → CONFLICT

Day 5 — after sync/squash to uat as S3
  uat:  A-S1-S3     ci.yml=NEW2
  main: A-S2        ci.yml=NEW1
  PR uat→main: merge-base A, both changed ci.yml → CONFLICT again
```

### 4.7 How to avoid this going forward (recommendations)

Pick one strategy and stick to it:

| Strategy | How | Tradeoff |
|----------|-----|----------|
| **Merge commits for promotions** | Turn off “Require linear history” on `uat`/`main`; use “Create a merge commit” | History has merge bubbles; ancestry stays intact → fewer fake conflicts |
| **Rebase then fast-forward** | Rebase `dev` onto `uat` before PR; FF merge | Needs discipline; force-push care |
| **Keep squash** | Accept periodic sync/repair PRs (like #13) | Conflicts will return |

For a **demo / portfolio** repo, merge commits on promotion edges are usually simpler.

---

## 5. Issues we faced

### 5.1 Tag ruleset accidentally targeted branches

First `protect-release-tags` used `target: branch` + `refs/heads/v*`.  
**Fix:** Tag ruleset on `refs/tags/v*` with create/update/delete only.

### 5.2 Required check name `promotion-guard / guard` vs `guard`

Ruleset expected `promotion-guard / guard`; job reported `guard`.  
**Fix:** `name: promotion-guard / guard` on the job (see §2.3).

### 5.3 PR author cannot approve own PR

`protect-main` required 1 review; author cannot approve themselves.  
**Fix:** Temporarily set approvals to 0, merge, restore.

### 5.4 Agent cannot push `v*` tags

Tag ruleset blocked the automation token.  
**Fix:** You pushed `v0.1.0` locally as maintainer.

### 5.5 Duplicate checks

See [§3](#3-duplicate-runs--detailed). Fixed with `decide`.

### 5.6 Squash history conflicts

See [§4](#4-squash-merge-conflicts--detailed). Repaired via sync merges + PR #13.

### 5.7 Infisical OIDC subject

Environment jobs get `sub` like:

```text
repo:sauravrana646@42442467/portfolio-secure-cicd@1321452770:environment:release
```

not the simple `repo:owner/repo:environment:release`.  
`@42442467` = GitHub user id; `@1321452770` = repo id (OIDC subject customization).

`oidc-debug` also failed once because Environment `release` only allows tags `v*` — `workflow_dispatch` on `main` was rejected before steps ran.

### 5.8 Cosign `invalid pem block`

Infisical auth worked; PEM in `cosign-private-key` was malformed (newlines/format).  
**Fix:** Re-store proper encrypted cosign PEM + password; re-run succeeded.

### 5.9 Agent permission gaps (403)

Could not: set Actions variables, create environments/rulesets, re-run jobs, approve reviews/environments. Those were UI steps.

---

## 6. Release `v0.1.0` outcome

| Item | Value |
|------|--------|
| Workflow | [success](https://github.com/sauravrana646/portfolio-secure-cicd/actions/runs/31281468291) |
| Tag | `v0.1.0` @ `e796a68` |
| Image | `ghcr.io/sauravrana646/portfolio-secure-cicd:v0.1.0` |
| Digest | `sha256:a407de4528243789ae9784099afbca03e066dcb9092f05f9ef3060b23145f1e3` |
| Cosign | `.sig` + `.att` on GHCR |
| SLSA | [attestation](https://github.com/sauravrana646/portfolio-secure-cicd/attestations/39619636) |
| GitHub Release | [v0.1.0](https://github.com/sauravrana646/portfolio-secure-cicd/releases/tag/v0.1.0) + `sbom.spdx.json` |

Verify locally:

```bash
IMAGE=ghcr.io/sauravrana646/portfolio-secure-cicd@sha256:a407de4528243789ae9784099afbca03e066dcb9092f05f9ef3060b23145f1e3
cosign verify --key cosign.pub "$IMAGE"
cosign verify-attestation --key cosign.pub --type spdx "$IMAGE"
gh attestation verify "oci://$IMAGE" --repo sauravrana646/portfolio-secure-cicd
```

---

## 7. Cleanup / next

- [ ] Remove temporary `main` allow from Environment `release` (keep tags `v*` only)
- [ ] Confirm `protect-main` again requires `promotion-guard / guard` + desired approval count
- [ ] Delete `.github/workflows/oidc-debug.yml` when no longer needed
- [ ] Decide promotion merge strategy (merge commit vs squash) to avoid §4 pain
- [ ] Step 8 later: update `devops-portfolio` website case study

---

## 8. Infisical / Environment quick reference

| Item | Value |
|------|--------|
| Project | `devops-portfolio-x-k3-y` |
| Env slug (release) | `prod` |
| Secret path | `/cosign` |
| Identity ID | `b0d5c6ed-5178-416d-80d2-cec4ee521424` |
| OIDC Subject (working) | `repo:sauravrana646@42442467/portfolio-secure-cicd@1321452770:environment:release` |
| Audience | `https://github.com/sauravrana646` |
| GitHub Environment | `release` (required reviewer, tags `v*`) |
| GitHub env vars | `INFISICAL_IDENTITY_ID`, `INFISICAL_ENV_SLUG` |
