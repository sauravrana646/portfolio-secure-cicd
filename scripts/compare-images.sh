#!/usr/bin/env bash
# Local before/after Trivy demo (requires trivy + docker)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Building hardened image =="
docker build -t portfolio-secure-cicd:hardened -f Dockerfile .

echo "== Building vulnerable image (local demo only) =="
docker build -t portfolio-secure-cicd:vulnerable -f Dockerfile.vulnerable .

if command -v trivy >/dev/null 2>&1; then
  echo "== Trivy: vulnerable =="
  trivy image --severity CRITICAL,HIGH --exit-code 0 portfolio-secure-cicd:vulnerable || true
  echo "== Trivy: hardened =="
  trivy image --severity CRITICAL,HIGH --exit-code 0 portfolio-secure-cicd:hardened || true
else
  echo "Install Trivy to compare: https://aquasecurity.github.io/trivy/"
fi
