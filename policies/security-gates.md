# Security gate policy

## Fail criteria (CI)

| Check | Action |
|-------|--------|
| Trivy filesystem scan — CRITICAL | Fail PR |
| Trivy image scan — CRITICAL | Fail PR |
| Unit tests | Fail PR |
| SBOM generation | Required artifact |

## `.trivyignore` rules

- Every ignore must include CVE ID, reason, and owner/ticket
- Ignores expire: re-review quarterly
- Never ignore CRITICAL without written risk acceptance

## Before → after hardening

| Practice | Vulnerable (`Dockerfile.vulnerable`) | Hardened (`Dockerfile`) |
|----------|--------------------------------------|-------------------------|
| Base image | Fat `python:3.9` | Slim bookworm + upgrade |
| User | root | UID 10001 non-root |
| Build | Single stage | Multi-stage venv copy |
| Secrets | Env anti-pattern | None in image |
| Runtime | `python` ad-hoc | gunicorn |

This mirrors engagements that cut container findings from 150+ to under 30 by fixing base images, removing packages, and failing PRs on CRITICAL.
