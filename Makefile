# Single entry point for the infra lifecycle (D-19). Workflows call these targets too.
# Run `make help` for the list. Must work with macOS's GNU Make 3.81.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---- Common variables --------------------------------------------------------

# Learner Lab only allows us-east-1 (AGENTS §4); `override` so neither env nor CLI can change it.
override AWS_REGION := us-east-1
CLUSTER_NAME ?= oncall-training

export AWS_REGION

# ---- Helpers -----------------------------------------------------------------

# Ask before anything destructive or billable (CONV §5). CONFIRM=yes skips it (CI only).
# Usage, as a recipe line:  $(call confirm,This destroys the cluster stack.)
define confirm
	@if [ "$(CONFIRM)" != "yes" ]; then \
	  printf '%s\nContinue? [y/N] ' "$(1)"; \
	  read -r answer || answer=""; \
	  case "$$answer" in [yY]) ;; *) echo "Aborted."; exit 1 ;; esac; \
	fi
endef

# ---- Targets -----------------------------------------------------------------
# A `## description` after a target name makes it show up in `make help`.

.PHONY: help
help: ## List targets
	@echo "Usage: make <target> [CONFIRM=yes]"
	@echo
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
	  | sed -E 's/^[^:]*:([a-zA-Z0-9_-]+):/\1:/' \
	  | awk -F ':.*## ' '{ printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }'
	@echo
	@echo "AWS_REGION=$(AWS_REGION)  CLUSTER_NAME=$(CLUSTER_NAME)"

# ---- Credentials -------------------------------------------------------------
# Every target that talks to AWS lists `check-creds` as its first prerequisite:
#   foundation-plan: check-creds

.PHONY: creds
creds: ## Paste the lab "AWS CLI" block → ~/.aws/credentials + GitHub secrets (SKIP_GH=1: local only)
	@scripts/lab-creds.sh

.PHONY: check-creds
check-creds: ## Fail early if the lab credentials are missing or expired
	@scripts/check-creds.sh

# ---- Bootstrap ---------------------------------------------------------------

TF_BOOTSTRAP := terraform -chdir=terraform/bootstrap

.PHONY: bootstrap
bootstrap: check-creds ## Once per lab account: create the state bucket, then write backend.hcl
	@$(TF_BOOTSTRAP) init -input=false
	@$(TF_BOOTSTRAP) plan -input=false -out=bootstrap.tfplan
	$(call confirm,This applies the bootstrap plan above.)
	@$(TF_BOOTSTRAP) apply -input=false bootstrap.tfplan
	@rm -f terraform/bootstrap/bootstrap.tfplan
	@$(MAKE) --no-print-directory backend-config

.PHONY: backend-config
backend-config: ## Write the gitignored backend.hcl for foundation and cluster from the bootstrap state
	@bucket="$$($(TF_BOOTSTRAP) output -raw state_bucket 2>/dev/null)"; \
	[ -n "$$bucket" ] || { \
	  echo "error: no state_bucket output; run make bootstrap (or import the bucket, see README)" >&2; exit 1; }; \
	for stack in foundation cluster; do \
	  printf 'bucket       = "%s"\nkey          = "%s.tfstate"\nregion       = "%s"\nuse_lockfile = true\nencrypt      = true\n' \
	    "$$bucket" "$$stack" "$(AWS_REGION)" > terraform/$$stack/backend.hcl; \
	  echo "Wrote terraform/$$stack/backend.hcl"; \
	done
