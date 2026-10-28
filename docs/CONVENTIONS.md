# Infra Conventions

Rules for Terraform, Kubernetes manifests, the state machine, the TypeScript services and the workflows in this repo. If one gets in the way, change it here in a PR and say why. Don't silently ignore it.

## 1. Terraform

### 1.1 Structure
- Each stack (`bootstrap`, `foundation`, `cluster`) is a root module with the same files:
  - `versions.tf` (terraform + provider versions, backend)
  - `providers.tf`
  - `variables.tf`
  - `locals.tf`
  - `outputs.tf`
  - **one file per concern** (`s3.tf`, `dynamodb.tf`, `sqs.tf`, `stepfunctions.tf`, `cognito.tf`, `cloudfront.tf`, `vpc.tf`, `eks.tf`, `elasticache.tf`…)
- Local modules in `terraform/modules/` only when something is repeated (e.g. `queue-with-dlq`). Don't create modules for single resources.
- **Prefer plain resources over community modules** (e.g. `terraform-aws-modules/eks`). Big modules create IAM roles, KMS keys and policies by default, which the Learner Lab forbids, and hide what's being created. Small, well-known modules (like the VPC module) are OK if every IAM-creating option is off. Each one needs a decision entry.

### 1.2 Versions
- `required_version = ">= 1.10"`. Providers pinned with `~>` (e.g. `aws ~> 6.0`, `helm ~> 3.0`). `.terraform.lock.hcl` committed.
- Helm charts and EKS add-on versions pinned explicitly; upgrade them in their own PR.

### 1.3 Naming and tags
- Resource names: `"${local.name}-<thing>"` with `local.name = "oncall-training"`. Add `-${local.account_id}` for globally unique names (S3, Cognito domain).
- Terraform addresses: snake_case, by role, not by type (`aws_sqs_queue.faults`, not `aws_sqs_queue.queue1`).
- Tags via `provider "aws" { default_tags { … } }`: `Project`, `Owner`, `Env`, `ManagedBy`, `Stack`. Add `Name` where the console shows it.

### 1.4 Learner Lab rules
- `data "aws_iam_role" "lab" { name = "LabRole" }` → `data.aws_iam_role.lab.arn` for every role argument.
- **Forbidden resource types** (CI fails if they appear; see §7):
  - `aws_iam_role`, `aws_iam_policy`, `aws_iam_role_policy`, `aws_iam_role_policy_attachment`, `aws_iam_user`
  - `aws_iam_openid_connect_provider`
  - `aws_eks_pod_identity_association`
  - `aws_s3_bucket`: use `awscc_s3_bucket` instead, with versioning, encryption, public access block and lifecycle set on that one resource and `tags = local.awscc_tags` (D-24). The other `aws_s3_bucket_*` resources that configure a bucket (versioning, encryption, public access block, lifecycle) aren't needed; `aws_s3_bucket_policy` is fine.
- Account id and region come from `data "aws_caller_identity"` / `data "aws_region"`. Never hardcode them.
- Instance types are variables with validation (`t3.*`/`t4g.*` up to `large`).

### 1.5 Variables and outputs
- Every variable has `type` and `description`; defaults only when there's a sensible one; `validation` blocks for enums and sizes.
- Every output has a `description`. Outputs other repos rely on are listed in ARCHITECTURE §3–4; treat renaming one as a contract change.
- Real values in `*.auto.tfvars` (gitignored); `terraform.tfvars.example` committed.

### 1.6 Safety
- `prevent_destroy` lifecycle on the DynamoDB table, the files bucket and the Cognito pool. `deletion_protection_enabled` on DynamoDB.
- Nothing billed hourly goes in `foundation`.
- Data never goes in `cluster` (destroying it must never lose sessions, logs or users).
- Security groups: least open; describe each rule; no `0.0.0.0/0` ingress except where ARCHITECTURE says so (none in the MVP; the ALB is limited to the CloudFront prefix list).
- Encryption at rest on for S3, DynamoDB and SQS; ElastiCache in-transit encryption on.

### 1.7 Workflow
- Before a PR: `terraform fmt -recursive`, `terraform validate`, `tflint`.
- The PR includes the `terraform plan` summary (adds/changes/destroys) for every stack it touches.
- `apply`/`destroy` only through `make` targets, which show the plan and ask for confirmation.

## 2. Kubernetes manifests (Kustomize)

- Layout: `k8s/base/<area>/` (namespaces, rbac, networkpolicies, app, injector, mock) and `k8s/overlays/{aws,local}`. Overlays change only images, Ingress, config and replica/resource tweaks; behavior lives in base.
- One resource per file, named `<kind>-<name>.yaml` (`deployment-backend-api.yaml`).
- **Labels** on everything:
  - `app.kubernetes.io/name: <workload>`
  - `app.kubernetes.io/part-of: oncall-training`
  - `app.kubernetes.io/component: api|worker|injector|mock`
  - Selectors use only `app.kubernetes.io/name`.
- **Every container has:**
  - `resources.requests` (cpu, memory) and `limits.memory`
  - liveness **and** readiness probes
  - security context (`runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`)
- **Images by immutable tag** (git SHA) through Kustomize `images:`; never `latest` in the aws overlay. In the local overlay: `imagePullPolicy: Never`.
- Config through the generated ConfigMap (`envFrom`); no hardcoded endpoints in Deployments.
- **RBAC:** namespaced `Role` + `RoleBinding` only, rules listed exactly as in ARCHITECTURE §5.2. No wildcards (`*`) in verbs or resources. ServiceAccounts that don't call the Kubernetes API set `automountServiceAccountToken: false`.
- **NetworkPolicies:** every namespace starts with `default-deny-ingress`; each allow policy has a comment saying who needs it.
- Singletons (`backend-worker`, `injector`) use `strategy: Recreate`.
- Validate locally: `kustomize build k8s/overlays/aws | kubeconform -strict -summary` (with CRD schemas for Ingress annotations not needed).

## 3. Step Functions

- One file: `statemachines/scenario.asl.json`, **JSONata** (`"QueryLanguage": "JSONata"` at the top level).
- Terraform placeholders use `${name}` (resolved by `templatefile`); runtime expressions use `{% … %}`. Don't mix them in one string.
- `Init` assigns input fields to variables (`$sessionId`, `$userId`, …). Later states use variables instead of threading the input through `Output`.
- State names are PascalCase verbs (`InjectFault`, `WaitForFix`). Every Task has a `Catch` that leads to `MarkFailed`, so every path ends with `SESSION_ENDED`.
- Every terminal path sends `SESSION_ENDED` (cross-repo, backend D-11). Add a test case when adding a path.
- Keep logic minimal: no scoring, no business rules. Those live in the backend.
- Test changes with the Step Functions **TestState** API on single states and one end-to-end run in the lab (`make sfn-smoke`), and copy the definition to the backend's `local/statemachine.asl.json`.

## 4. TypeScript services (injector, mock system)

The same base rules as the backend repo (see its CONVENTIONS), summarized:
- Node 22, TypeScript `strict`, ESM (`"type": "module"`, `NodeNext`, `.js` import extensions), pnpm workspace (`services/*`).
- zod for env vars and messages; pino JSON logs (with `faultId`/`sessionId` context); no `console.log`.
- AWS SDK v3 clients with the default credential chain; never pass `credentials`; honor `AWS_ENDPOINT_URL` locally.
- Kubernetes calls only in a small gateway module, always namespaced with `MOCK_NAMESPACE`; targets checked against the allowed list before any call.
- Handlers are idempotent; SQS messages are deleted only after success; `SIGTERM` handling.
- Vitest unit tests:
  - injector: message parsing, target validation, idempotent apply/record order (with fakes)
  - mock system: health chain logic and timeouts
- Dockerfiles: multi-stage, `node:22-alpine`, `USER node`, `.dockerignore`.

## 5. Scripts and Makefile

- Scripts are bash with `set -euo pipefail`, `shellcheck`-clean, and print what they're about to do.
- Every destructive or billable `make` target shows the plan or affected resources and asks `Continue? [y/N]`. `CONFIRM=yes` skips the prompt (CI only).
- Make targets are the single entry point. Workflows call `make <target>`, never duplicate the commands.
- `make creds` never echoes secrets; it writes `~/.aws/credentials` with `600` permissions and uses `gh secret set` reading from stdin.

## 6. GitHub Actions

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yml` | PR, push to `main` | fmt/validate/tflint, forbidden-IAM check, kustomize + kubeconform, checkov (soft-fail), pnpm lint/typecheck/test, docker build (no push). **Never needs AWS.** |
| `images.yml` | push to `main` (paths `services/**`), manual | build + push injector and mock-system to ECR |
| `cluster.yml` | manual, input `action: up \| down` | `make cluster-up` / `make cluster-down` with `CONFIRM=yes` |
| `deploy.yml` | manual, inputs `backend_tag`, `injector_tag`, `mock_tag` | `make deploy …`, commits the updated `images.env` |

- AWS credentials come from the Learner Lab secrets refreshed by `make creds` (DECISIONS D-19). A workflow that needs AWS checks them first (`aws sts get-caller-identity`) and fails with "Lab credentials expired — run make creds".
- `concurrency` group per workflow so two cluster runs never overlap.
- Pin third-party actions by commit SHA.

## 7. Policy checks

- CI greps the Terraform code for the forbidden resource types (§1.4) and fails if it finds any.
- `checkov` runs soft-fail. Real findings are fixed or suppressed inline with a reason (`#checkov:skip=CKV_…: reason`).

## 8. Git and PRs

- Branches from `main`: `infra/…`, `k8s/…`, `sfn/…`, `svc/…`, `ci/…`, `docs/…`.
- Conventional Commits: `feat(cluster): add ElastiCache Valkey replication group`.
- PR description: what, why, `terraform plan` summary, cost impact (if any), and whether the backend or frontend needs to act (contract change).
- The other teammate reviews PRs that change a cross-repo contract (queue messages, state machine I/O, RBAC, ConfigMap keys, outputs).
- Docs move with code: contracts go in `ARCHITECTURE.md`, decisions in `DECISIONS.md`.
