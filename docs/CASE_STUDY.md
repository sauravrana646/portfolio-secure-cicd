# Case Study: Secure CI/CD & Container Hardening

## Client type

Anonymized: Series-A SaaS (fintech-adjacent) shipping weekly to Kubernetes

## Problem

Container images and CI pipelines had no CRITICAL severity gate. Scans ran as optional warnings. Production images regularly showed **150+** findings (mixed severities), including outdated base images and root runtimes. Anyone could merge into “prod” without a promotion path, and released images were unsigned — no SBOM attestation or provenance consumers could verify. Leadership wanted shipping speed without becoming a ticket queue for security.

## Approach

1. Introduce fail-on-CRITICAL Trivy gates on PRs (filesystem + image)
2. Multi-stage, non-root Dockerfiles; slim bases; remove build tools from runtime
3. Generate SBOM on every build; upload SARIF to GitHub Security
4. Enforce linear promotion: `feature/*` → `dev` → `uat` → `main` (prod) via PR checks + a promotion-guard workflow (source-branch enforcement GitHub cannot do natively)
5. Manual semver tag release from `main`: push to GHCR by tag + digest, sign and attest with cosign (private key via Infisical OIDC), attach Syft SPDX SBOM attestation, emit SLSA build provenance, publish a GitHub Release with changelog
6. Document `.trivyignore` policy with owners and expiry
7. Optional OIDC deploy path so CI never stores long-lived cloud keys

## Stack

- GitHub Actions (reusable quality-gate + promotion-guard + release)
- Trivy (fs + image)
- Syft (SBOM)
- GHCR
- Cosign (sign + SPDX attest; key material from Infisical OIDC)
- SLSA provenance (`actions/attest-build-provenance`)
- Docker multi-stage / gunicorn
- Python 3.12

## Promotion & signed release narrative

```text
feature/* ──PR──► dev ──PR (guard)──► uat ──PR (guard)──► main
                                                              │
                                                         tag vX.Y.Z
                                                              ▼
                         quality-gate → GHCR digest → cosign sign/attest
                         → SLSA provenance → GitHub Release + SBOM
```

- **Quality gate** runs on every PR/push to `dev`, `uat`, and `main`.
- **Promotion guard** fails PRs into `uat` unless the source is `dev`, and into `main` unless the source is `uat`.
- **Release** signs the **digest** (`@sha256:...`), never a mutable tag alone. Consumers pull `:vX.Y.Z` and verify against the digest recorded in the release notes.
- Cosign keys stay in Infisical (`homelab-sq-te` / `/cosign`); the release job federates via OIDC using a machine identity — no cosign private key stored as a GitHub Actions secret.

## Results (from real experience / analogous)

Example results from analogous engagements — not guarantees for your environment:

- Container vulnerability counts cut from **150+ → under 30** by base-image and privilege fixes
- CIS-oriented hardening for build/runtime; hardened AMI patterns on the infra side of similar projects
- PR feedback loop: CRITICAL findings block merge until fixed or explicitly risk-accepted
- Promotion path prevents accidental “feature straight to prod” merges
- Released images are verifiable: cosign signature, SBOM attestation, and GitHub provenance

## What I deliver in a freelance engagement

- **Timeline:** typically 1–2 weeks for one app (staging + prod pipelines)
- **Fixed-scope offer:** Security Hardening sprint — CI gates, Dockerfile hardening, SBOM, promotion model, signed release, policy doc, handoff
- **Out of scope:** full penetration test, legal/compliance attestation, rewriting the application business logic

### CTA

Hire for a **Security Hardening sprint** — [sauravrana646@gmail.com](mailto:sauravrana646@gmail.com)
