# Security Policy

## Supported versions

This is a public portfolio demo. Use the latest `main` (or tagged releases such as `v1.0.0`).

## Reporting a vulnerability

Email **sauravrana646@gmail.com** with:

- Repo name and commit SHA
- Description and reproduction steps
- Whether the finding is in the demo app, Dockerfile, CI, or docs

Please do **not** open a public issue for sensitive findings until we have a chance to respond (usually within a few business days).

## Demo notes

- `Dockerfile.vulnerable` / `demo/fail-critical` exist only to show fail-on-CRITICAL gates. Do not deploy them.
- Never commit real cloud credentials. Prefer GitHub OIDC to AWS for any staging deploy.
