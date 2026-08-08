# Security gate policy

## Fail criteria (CI) — all of `dev`, `uat`, `main`

Shared reusable workflow: `.github/workflows/quality-gate.yml` (invoked by `ci.yml` and `release.yml`).

| Check | Action |
|-------|--------|
| Trivy filesystem scan — CRITICAL | Fail check |
| Trivy image scan — CRITICAL | Fail check |
| Unit tests | Fail check |
| SBOM generation (Syft) | Required artifact |

## Promotion guard

Workflow: `.github/workflows/promotion-guard.yml` (required on `uat` and `main`).

| Target branch | Allowed source | On violation |
|---------------|----------------|--------------|
| `uat` | `dev` only | Fail: "uat only accepts merges from dev" |
| `main` (prod) | `uat` only | Fail: "main (prod) only accepts merges from uat" |
| `dev` | any (`feature/*`, etc.) | No promotion-guard; quality-gate only |

`feature/*` → `dev` is unrestricted by source. There is no separate `prod` branch; `main` is prod.

## Release gate (manual tag `vX.Y.Z` on `main`)

Job uses GitHub Environment **`release`** (required reviewer; deployment tag policy `v*` only).

| Check | Action |
|-------|--------|
| Re-run quality-gate | Fail release if CRITICAL / tests fail |
| Environment approval | `release` job waits until a required reviewer approves |
| Tag policy | Only refs matching tag pattern `v*` may use `release` |
| GHCR push | Tags `:vX.Y.Z` and `:<sha>`; canonical identity is digest |
| Cosign sign + verify | Sign digest with Infisical-backed key |
| Cosign SPDX attest | Attest Syft `sbom.spdx.json` to digest |
| SLSA provenance | `actions/attest-build-provenance` on digest |
| GitHub Release | Changelog + SBOM attachment + digest mapping |

## `.trivyignore` rules

- Every ignore must include CVE ID, reason, and owner/ticket
- Ignores expire: re-review quarterly
- Never ignore CRITICAL without written risk acceptance

## Before → after hardening

| Dimension | Vulnerable (`Dockerfile.vulnerable`) | Hardened (`Dockerfile`) |
|----------|--------------------------------------|-------------------------|
| Base image | Fat `python:3.9` | Slim bookworm + upgrade |
| User | root | UID 10001 non-root |
| Build | Single stage | Multi-stage venv copy |
| Secrets | Env anti-pattern | None in image |
| Runtime | `python` ad-hoc | gunicorn |

This mirrors engagements that cut container findings from 150+ to under 30 by fixing base images, removing packages, and failing PRs on CRITICAL.

## Branch protection (apply in GitHub UI)

See `docs/BRANCH_PROTECTION_UI.md` for step-by-step UI instructions. Summary of intended rules:

| Branch | Require PR | Required checks | Extra |
|--------|------------|-----------------|-------|
| `dev` | Yes | `quality-gate / test`, `quality-gate / security` | No direct pushes |
| `uat` | Yes | above + `promotion-guard / guard` | Require up-to-date; linear history |
| `main` | Yes | same as `uat` | Optional required reviews |
| Tags `v*` | — | — | Restrict creation to maintainers |
