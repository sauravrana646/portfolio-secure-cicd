.PHONY: help up down test lint scan sbom compare
help:
	@echo "Targets: up down test lint scan compare"

up:
	docker compose up --build -d

down:
	docker compose down

test:
	PYTHONPATH=. pytest -q

lint:
	python -m compileall app

scan:
	docker build -t portfolio-secure-cicd:local -f Dockerfile .
	@command -v trivy >/dev/null && trivy image --severity CRITICAL --exit-code 1 portfolio-secure-cicd:local || echo "Install trivy for local scan"

compare:
	./scripts/compare-images.sh

# Terraform not used in this repo; stubs for shared Makefile convention
plan:
	@echo "No Terraform in portfolio-secure-cicd"

apply:
	@echo "No Terraform apply — see policies/oidc-aws-deploy-stub.md"
