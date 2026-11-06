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
	@scripts/bootstrap-account.sh
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

# ---- Foundation and cluster stacks -------------------------------------------
# Both use the S3 backend from backend.hcl (written by `make backend-config`).
# Plans are saved to <stack>.tfplan so apply runs exactly what was shown.

TF_FOUNDATION := terraform -chdir=terraform/foundation
TF_CLUSTER    := terraform -chdir=terraform/cluster

# $(call tf_init,<stack>): checks backend.hcl is for the current account, then init -reconfigure.
define tf_init
	@scripts/tf-init.sh $(1)
endef

.PHONY: foundation-plan
foundation-plan: check-creds ## Plan the foundation stack (S3, DynamoDB, SQS, ECR, ...)
	$(call tf_init,foundation)
	@$(TF_FOUNDATION) plan -input=false -out=foundation.tfplan

.PHONY: foundation-apply
foundation-apply: foundation-plan ## ⚠ Apply the foundation plan (asks first)
	$(call confirm,This applies the foundation plan above.)
	@$(TF_FOUNDATION) apply -input=false foundation.tfplan
	@rm -f terraform/foundation/foundation.tfplan

.PHONY: foundation-output
foundation-output: check-creds ## Show the foundation outputs (queue URLs, table, ECR URLs) to share with the team
	$(call tf_init,foundation)
	@$(TF_FOUNDATION) output

.PHONY: cluster-plan
cluster-plan: check-creds ## Plan the cluster stack (VPC, EKS, nodes, add-ons, LB controller)
	$(call tf_init,cluster)
	@$(TF_CLUSTER) plan -input=false -out=cluster.tfplan

# ---- Cluster lifecycle (ARCHITECTURE §13) ------------------------------------
# ⚠ The cluster bills ≈ $0.25/h while it's up. cluster-down at the end of every session.

.PHONY: cluster-up
cluster-up: cluster-plan ## ⚠ Create the cluster, render config, apply k8s/overlays/aws (~20 min, billable)
	@[ -f terraform/cluster/cluster.auto.tfvars ] || \
	  echo "warning: no terraform/cluster/cluster.auto.tfvars; the ALB will accept no traffic (alb_ingress_cidrs = [])"
	$(call confirm,This creates the EKS cluster (≈ \$$0.25/h until make cluster-down).)
	@$(TF_CLUSTER) apply -input=false cluster.tfplan
	@rm -f terraform/cluster/cluster.tfplan
	@aws eks update-kubeconfig --region $(AWS_REGION) --name $(CLUSTER_NAME)
	@$(MAKE) --no-print-directory render-config
	@CLUSTER_NAME=$(CLUSTER_NAME) scripts/k8s-apply.sh
	@CLUSTER_NAME=$(CLUSTER_NAME) scripts/status.sh

.PHONY: cluster-down
cluster-down: check-creds ## ⚠ Delete the Ingress (ALB), wait, then destroy the cluster stack
	$(call confirm,This destroys the cluster stack. Foundation (data, users, images) stays up.)
	@CLUSTER_NAME=$(CLUSTER_NAME) scripts/cluster-down-wait.sh
	$(call tf_init,cluster)
	@$(TF_CLUSTER) destroy -input=false -auto-approve
	@echo "Cluster destroyed. Foundation stays up (cents per day)."

.PHONY: render-config
render-config: check-creds ## Write k8s/overlays/aws/{config,cluster}.env from the Terraform outputs
	$(call tf_init,foundation)
	$(call tf_init,cluster)
	@scripts/render-config.sh

.PHONY: deploy
deploy: check-creds ## ⚠ Roll out images: make deploy [BACKEND_TAG=<sha>] [INJECTOR_TAG=<sha>] [MOCK_TAG=<sha>]
	$(call confirm,This rolls out BACKEND_TAG=$(BACKEND_TAG) INJECTOR_TAG=$(INJECTOR_TAG) MOCK_TAG=$(MOCK_TAG) on EKS.)
	@aws eks update-kubeconfig --region $(AWS_REGION) --name $(CLUSTER_NAME) >/dev/null
	@CLUSTER_NAME=$(CLUSTER_NAME) scripts/deploy.sh BACKEND_TAG=$(BACKEND_TAG) INJECTOR_TAG=$(INJECTOR_TAG) MOCK_TAG=$(MOCK_TAG)

.PHONY: status
status: check-creds ## Nodes, pods per namespace, ALB DNS, image tags, cost reminder
	@CLUSTER_NAME=$(CLUSTER_NAME) scripts/status.sh

.PHONY: check-rbac
check-rbac: ## Check the RBAC of ARCHITECTURE §5.2 on the current cluster (read-only)
	@scripts/check-rbac.sh

# ---- Images ------------------------------------------------------------------

.PHONY: images
images: check-creds ## Build + push injector and mock-system to ECR (linux/amd64, git SHA tag)
	$(call tf_init,foundation)
	@scripts/images.sh

# ---- Checks (no AWS) ---------------------------------------------------------

.PHONY: k8s-validate
k8s-validate: ## kustomize build + kubeconform for base and overlays
	@scripts/k8s-validate.sh

.PHONY: test
test: ## Unit tests of the injector and mock system
	@pnpm test

# ---- Docs --------------------------------------------------------------------

.PHONY: diagram
diagram: ## Render docs/solucion.mmd → docs/solucion.png (needs Node; downloads mermaid-cli)
	@npx -y @mermaid-js/mermaid-cli@11 -i docs/solucion.mmd -o docs/solucion.png -w 2400 -s 2 -b white
