# Case Study: Secure CI/CD & Container Hardening

## Client type

Anonymized: Series-A SaaS (fintech-adjacent) shipping weekly to Kubernetes

## Problem

Container images and CI pipelines had no CRITICAL severity gate. Scans ran as optional warnings. Production images regularly showed **150+** findings (mixed severities), including outdated base images and root runtimes. Leadership wanted shipping speed without becoming a ticket queue for security.

## Approach

1. Introduce fail-on-CRITICAL Trivy gates on PRs (filesystem + image)
2. Multi-stage, non-root Dockerfiles; slim bases; remove build tools from runtime
3. Generate SBOM on every build; upload SARIF to GitHub Security
4. Document `.trivyignore` policy with owners and expiry
5. Optional OIDC deploy path so CI never stores long-lived cloud keys

## Stack

- GitHub Actions
- Trivy (fs + image)
- Syft (SBOM)
- Docker multi-stage / gunicorn
- Python 3.12

## Results (from real experience / analogous)

Example results from analogous engagements — not guarantees for your environment:

- Container vulnerability counts cut from **150+ → under 30** by base-image and privilege fixes
- CIS-oriented hardening for build/runtime; hardened AMI patterns on the infra side of similar projects
- PR feedback loop: CRITICAL findings block merge until fixed or explicitly risk-accepted

## What I deliver in a freelance engagement

- **Timeline:** typically 1–2 weeks for one app (staging + prod pipelines)
- **Fixed-scope offer:** Security Hardening sprint — CI gates, Dockerfile hardening, SBOM, policy doc, handoff
- **Out of scope:** full penetration test, legal/compliance attestation, rewriting the application business logic

### CTA

Hire for a **Security Hardening sprint** — [sauravrana646@gmail.com](mailto:sauravrana646@gmail.com)
