# Infra Backlog

Small, single-concern issues for `oncall-training-infra`, from repo setup to final polish. Infra scope only: backend and frontend work isn't listed, except where this repo has to hand something to them (`cross-repo`).
Section references (§) point to `ARCHITECTURE.md` unless stated otherwise. `CONV` = `CONVENTIONS.md`, `D-xx` / `O-xx` / `F-xx` = `DECISIONS.md`.

**Format.** Every issue has one heading `### INF-NNN · <title>`, then one metadata line, then a short description and a "Done when" checklist. Keep that shape so the backlog can be turned into GitHub issues by a script.

**Milestones**

| Milestone | Target | Goal |
|---|---|---|
| `M0 · Setup` | Tue Oct 27 | Repo skeleton, tooling, creds, state bucket |
| `M1 · EKS up` | **Thu Oct 29** | Foundation basics + EKS; backend, mock system and injector running in separate namespaces; injector kills, system can be revived |
| `M2 · Orchestration` | **Thu Nov 19** | Step Functions + both SQS queues integrated; ElastiCache serving the dashboard; CloudFront + Cognito |
| `M3 · Data + e2e` | **Thu Nov 26** | Glue/Athena ready; e2e happy path on the deployed stack |
| `M4 · Polish` | after Nov 26 | Docs, hardening, CV polish, stretch items |

**Labels:** `area:repo` `area:terraform` `area:k8s` `area:sfn` `area:svc` `area:ops` `area:ci` `area:docs` · `stack:bootstrap` `stack:foundation` `stack:cluster` · `svc:injector` `svc:mock` · `type:task` `type:spike` · `cross-repo` · `billable` (creates hourly-billed resources) · `applies-aws` (needs a confirmed apply in the lab).

---

## 0. Repository setup (M0)

### INF-001 · Move ARCHITECTURE, CONVENTIONS and DECISIONS into docs/
`labels: area:docs, type:task` · `milestone: M0 · Setup` · `depends: —`

AGENTS.md and the docs cross-reference `docs/*.md`, but the files are at the repo root.
- [ ] `git mv` the three files into `docs/`
- [ ] All relative links in AGENTS.md and the docs resolve

### INF-002 · Add .gitignore for Terraform, Node, kube and local config
`labels: area:repo, type:task` · `milestone: M0 · Setup` · `depends: —`

- [ ] Ignores `.terraform/`, `*.tfstate*`, `*.tfvars` (except `*.tfvars.example`), `*.auto.tfvars`, `backend.hcl`, `k8s/overlays/aws/config.env`, `node_modules/`, `dist/`, `coverage/`, `*.kubeconfig`, `.env*`
- [ ] Does **not** ignore `.terraform.lock.hcl` or `k8s/overlays/aws/images.env`

### INF-003 · Create the directory skeleton from AGENTS §7
`labels: area:repo, type:task` · `milestone: M0 · Setup` · `depends: INF-001`

- [ ] `terraform/{bootstrap,foundation,cluster,modules}`, `statemachines/`, `k8s/base/{namespaces,rbac,networkpolicies,app,injector,mock}`, `k8s/overlays/{aws,local}`, `services/{injector,mock-system}`, `scripts/`, `.github/workflows/` exist (with `.gitkeep` where empty)

### INF-004 · Pin tool versions (.tool-versions / mise)
`labels: area:repo, type:task` · `milestone: M0 · Setup` · `depends: —`

- [ ] Pinned: terraform ≥ 1.10, tflint, kubectl, kustomize, kubeconform, kind, helm, node 22, pnpm, shellcheck, awscli v2
- [ ] README lists how to install them (`mise install`)

### INF-005 · Add .editorconfig and pre-commit hooks
`labels: area:repo, type:task` · `milestone: M0 · Setup` · `depends: INF-004`

- [ ] `.editorconfig` (2 spaces, LF, final newline)
- [ ] `.pre-commit-config.yaml` with `terraform_fmt`, `terraform_validate`, `shellcheck`, trailing-whitespace

### INF-006 · Create GitHub labels and milestones
`labels: area:repo, type:task` · `milestone: M0 · Setup` · `depends: —`

- [ ] The labels and milestones at the top of this file exist in the GitHub repo (via `gh label create` / `gh api`)

### INF-007 · Add PR and issue templates
`labels: area:repo, type:task` · `milestone: M0 · Setup` · `depends: —`

- [ ] `.github/pull_request_template.md` has: what, why, `terraform plan` summary per stack, cost impact, contract change (backend/frontend action needed)
- [ ] `.github/ISSUE_TEMPLATE/task.md` matches the format of this backlog

### INF-008 · Add CODEOWNERS and protect main
`labels: area:repo, type:task` · `milestone: M1 · EKS up` · `depends: INF-114`

- [ ] CODEOWNERS: Ian on everything; JP also on contract files (`statemachines/`, `k8s/base/rbac/`, `k8s/base/app/`, foundation `outputs.tf`)
- [ ] Branch protection on `main`: PR required, `ci.yml` checks required

### INF-009 · Makefile skeleton with help and a confirm helper
`labels: area:ops, type:task` · `milestone: M0 · Setup` · `depends: INF-003`

- [ ] `make help` lists targets with one-line descriptions
- [ ] A shared `confirm` macro prints `Continue? [y/N]`; `CONFIRM=yes` skips it (CONV §5)
- [ ] Common variables: `AWS_REGION=us-east-1`, `CLUSTER_NAME=oncall-training`

### INF-010 · Write the README quick start
`labels: area:docs, type:task` · `milestone: M0 · Setup` · `depends: INF-001, INF-004`

- [ ] What the repo is, links to AGENTS and docs, prerequisites, the lab session routine (§13.1) with the **`make cluster-down` warning**
- [ ] Gets expanded in INF-150

---

## 1. Lab credentials (M0)

### INF-011 · scripts/lab-creds.sh: write ~/.aws/credentials from the pasted lab block
`labels: area:ops, type:task` · `milestone: M0 · Setup` · `depends: INF-003`

- [ ] Reads the Learner Lab "AWS CLI" block from stdin, writes the `default` profile, `chmod 600`
- [ ] Never echoes the secret values; `set -euo pipefail`; shellcheck-clean
- [ ] Ends with `aws sts get-caller-identity` (prints the account id only)

### INF-012 · lab-creds.sh: push the creds as GitHub secrets to the 3 repos
`labels: area:ops, type:task, cross-repo` · `milestone: M0 · Setup` · `depends: INF-011`

- [ ] `gh secret set` (value from stdin) `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` in infra, backend and frontend repos
- [ ] Repo list configurable through an env var; skip with `SKIP_GH=1`

### INF-013 · make creds and a reusable credential check
`labels: area:ops, type:task` · `milestone: M0 · Setup` · `depends: INF-009, INF-012`

- [ ] `make creds` runs `lab-creds.sh`
- [ ] `scripts/check-creds.sh` fails with "Lab credentials expired — run make creds"; every AWS-touching make target calls it first

---

## 2. Bootstrap stack (M0)

### INF-014 · Bootstrap stack scaffold
`labels: area:terraform, stack:bootstrap, type:task` · `milestone: M0 · Setup` · `depends: INF-003`

- [ ] `versions.tf` (terraform ≥ 1.10, aws ~> 6.0, local backend), `providers.tf` (us-east-1, default tags with `Stack=bootstrap`), `variables.tf`, `locals.tf`, `outputs.tf`
- [ ] `data "aws_caller_identity"` for the account id; `.terraform.lock.hcl` committed

### INF-015 · Terraform state bucket
`labels: area:terraform, stack:bootstrap, type:task, applies-aws` · `milestone: M0 · Setup` · `depends: INF-014`

- [ ] `oncall-training-tfstate-<acct>`: versioning on, SSE-S3, block public access, `prevent_destroy`
- [ ] Output `state_bucket`
- [ ] README note on recreating local state with `terraform import` (§2)

### INF-016 · make bootstrap and backend.hcl generation
`labels: area:ops, stack:bootstrap, type:task, applies-aws` · `milestone: M0 · Setup` · `depends: INF-015, INF-013`

- [ ] `make bootstrap` runs plan → confirm → apply
- [ ] Writes gitignored `terraform/foundation/backend.hcl` and `terraform/cluster/backend.hcl` (bucket, key, region, `use_lockfile = true`, `encrypt = true`)
- [ ] Applied once in Ian's lab account

---

## 3. Foundation stack (M1–M3)

### INF-017 · Foundation stack scaffold
`labels: area:terraform, stack:foundation, type:task` · `milestone: M1 · EKS up` · `depends: INF-016`

- [ ] Standard files (CONV §1.1); S3 backend via `-backend-config=backend.hcl`
- [ ] Default tags `Project, Owner, Env=lab, ManagedBy=terraform, Stack=foundation`
- [ ] Data sources: caller identity, region, `aws_iam_role.lab` (LabRole); `local.name`, `local.account_id`
- [ ] `terraform.tfvars.example` committed

### INF-018 · make foundation-plan and make foundation-apply
`labels: area:ops, stack:foundation, type:task` · `milestone: M1 · EKS up` · `depends: INF-017, INF-009`

- [ ] `foundation-plan` runs `init` + `plan -out`; `foundation-apply` shows the plan, confirms, applies the saved plan
- [ ] Both call the credential check

### INF-019 · S3 files bucket
`labels: area:terraform, stack:foundation, type:task` · `milestone: M1 · EKS up` · `depends: INF-017`

- [ ] `awscc_s3_bucket` `oncall-training-files-<acct>` (not `aws_s3_bucket`, D-24): block public access, SSE-S3, versioning off, `prevent_destroy`
- [ ] Lifecycle rule: `athena-results/` expires after 7 days
- [ ] Output `files_bucket`

### INF-020 · DynamoDB Sessions table
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-017`

- [ ] On-demand, PK `user_id` (S), SK `session_id` (S), PITR on, deletion protection on, `prevent_destroy`
- [ ] GSI `Leaderboard` (PK `scenario_id` S, SK `score` N, projection ALL)
- [ ] Output `sessions_table`

### INF-021 · Local module queue-with-dlq
`labels: area:terraform, stack:foundation, type:task` · `milestone: M1 · EKS up` · `depends: INF-017`

- [ ] `terraform/modules/queue-with-dlq`: inputs `name`, `fifo`, `visibility_timeout`, `retention`, `max_receive_count`; creates the queue + DLQ + redrive policy, SSE-SQS
- [ ] FIFO: `.fifo` suffix on both queues, content-based dedup **off**
- [ ] Outputs `url`, `arn`, `dlq_url`, `dlq_arn`

### INF-022 · SQS faults queue + DLQ
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-021`

- [ ] `oncall-training-faults` + `-faults-dlq`: standard, visibility 60 s, retention 1 day, `maxReceiveCount = 3`
- [ ] Output `faults_queue_url`

### INF-023 · SQS user-actions.fifo + DLQ
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-021`

- [ ] `oncall-training-user-actions.fifo` + `-user-actions-dlq.fifo`, visibility 60 s, `maxReceiveCount = 3`
- [ ] Output `user_actions_queue_url`

### INF-024 · ECR repositories
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-017`

- [ ] `oncall-training/backend`, `/injector`, `/mock-system`: immutable tags, scan on push
- [ ] Lifecycle policy: keep the last 15 images
- [ ] Output `ecr_repository_urls` (map)

### INF-025 · First foundation apply (S3 files, DynamoDB, SQS, ECR)
`labels: area:ops, stack:foundation, type:task, applies-aws` · `milestone: M1 · EKS up` · `depends: INF-018, INF-019, INF-020, INF-022, INF-023, INF-024`

- [ ] `make foundation-apply` succeeds in Ian's lab account; plan summary pasted in the PR/issue
- [ ] Outputs shared with JP (backend CI variables)

### INF-026 · S3 site bucket
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-017`

- [ ] `awscc_s3_bucket` `oncall-training-site-<acct>` (not `aws_s3_bucket`, D-24): block public access, SSE-S3 (the bucket policy comes in INF-029)
- [ ] Output `site_bucket`

### INF-027 · CloudFront Function spa-rewrite
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-017`

- [ ] JS source in `terraform/foundation/functions/spa-rewrite.js`: a URI without a file extension → `/index.html`
- [ ] `aws_cloudfront_function` (runtime `cloudfront-js-2.0`, `publish = true`)
- [ ] Unit test for the rewrite (e.g. Vitest on the file, or `aws cloudfront test-function` documented)

### INF-028 · CloudFront distribution with the S3 site origin (OAC)
`labels: area:terraform, stack:foundation, type:task` · `milestone: M2 · Orchestration` · `depends: INF-026, INF-027`

- [ ] OAC (sigv4, always) + distribution; default behavior → site bucket, `Managed-CachingOptimized`, viewer-request `spa-rewrite`
- [ ] Redirect HTTP → HTTPS, `PriceClass_100`, default root object `index.html`, default certificate, **no custom error responses**
- [ ] Outputs `cloudfront_domain`, `cloudfront_distribution_id`

### INF-029 · Site bucket policy for CloudFront OAC
`labels: area:terraform, stack:foundation, type:task` · `milestone: M2 · Orchestration` · `depends: INF-028`

- [ ] Allows `s3:GetObject` only to `cloudfront.amazonaws.com` with `AWS:SourceArn` = this distribution

### INF-030 · CloudFront /api/* behavior with an ALB origin variable
`labels: area:terraform, stack:foundation, type:task` · `milestone: M2 · Orchestration` · `depends: INF-028`

- [ ] Variable `api_origin_domain` (default `"api-origin.invalid"`), HTTP-only origin on port 80
- [ ] Behavior `/api/*`: all methods, `Managed-CachingDisabled`, `Managed-AllViewerExceptHostHeader`
- [ ] Plans clean with the default value (`/api/*` returns 502 while the cluster is down)

### INF-031 · Cognito user pool
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-017`

- [ ] `oncall-training-users`: email sign-in, self sign-up, email verification, default email sender, `prevent_destroy`
- [ ] Output `cognito_user_pool_id`

### INF-032 · Cognito managed login domain
`labels: area:terraform, stack:foundation, type:task` · `milestone: M2 · Orchestration` · `depends: INF-031`

- [ ] Domain `oncall-training-<acct>`, managed login version 2 with default branding
- [ ] Output `cognito_domain`

### INF-033 · Cognito public app client (PKCE)
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-031, INF-028`

- [ ] No secret, auth code flow, scopes `openid email profile`, refresh tokens on, access token 60 min
- [ ] Callbacks `https://<cloudfront_domain>/callback`, `http://localhost:5173/callback`; logout `https://<cloudfront_domain>/`, `http://localhost:5173/`
- [ ] Output `cognito_client_id`

### INF-034 · scripts/create-e2e-user.sh
`labels: area:ops, type:task` · `milestone: M3 · Data + e2e` · `depends: INF-031`

- [ ] `admin-create-user` + `admin-set-user-password --permanent` with the password from an env var (D-22); idempotent if the user exists
- [ ] Not in Terraform; the password never printed

### INF-035 · Step Functions log group and state machine resource
`labels: area:terraform, area:sfn, stack:foundation, type:task` · `milestone: M2 · Orchestration` · `depends: INF-017, INF-040`

- [ ] Log group `/aws/states/oncall-training-scenario`, 14-day retention
- [ ] `aws_sfn_state_machine` `oncall-training-scenario`: Standard, role = LabRole, `templatefile()` with queue URLs and table name, logging level `ERROR`
- [ ] Output `state_machine_arn`

### INF-036 · Glue database and session_events table with partition projection
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M3 · Data + e2e` · `depends: INF-019`

- [ ] Database `oncall_training`; table `session_events` at `s3://…files…/logs/`, OpenX JSON SerDe, the columns in §10.2
- [ ] Partition keys `year, month, day` with projection (ranges, digits, `storage.location.template`)
- [ ] Output `glue_database`

### INF-037 · Athena workgroup
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M3 · Data + e2e` · `depends: INF-019`

- [ ] `oncall-training`: enforced output `s3://…files…/athena-results/`, `bytes_scanned_cutoff_per_query = 100 MB`, engine v3
- [ ] Output `athena_workgroup`

### INF-038 · Verify Athena queries against sample logs
`labels: area:ops, stack:foundation, type:spike` · `milestone: M3 · Data + e2e` · `depends: INF-036, INF-037`

- [ ] Upload a sample JSON-lines file under `logs/year=…/month=…/day=…/`, run a `SELECT … WHERE year/month/day` through the workgroup, confirm projection works with no crawler
- [ ] Remove the sample file afterwards

### INF-039 · Review foundation outputs against ARCHITECTURE §3
`labels: area:terraform, stack:foundation, type:task, cross-repo` · `milestone: M3 · Data + e2e` · `depends: INF-025, INF-028, INF-033, INF-035, INF-037`

- [ ] Every output listed in §3 exists with a `description`; no extras that other repos might start depending on by accident

---

## 4. State machine (M2)

### INF-040 · ASL skeleton: Init, Warmup, Succeed (JSONata)
`labels: area:sfn, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-003`

- [ ] `statemachines/scenario.asl.json` with `"QueryLanguage": "JSONata"`; `Init` assigns `$userId, $sessionId, $scenarioId, $warmupSeconds, $maxResolveSeconds, $fault`
- [ ] `Warmup` waits `$warmupSeconds`
- [ ] Renders with `templatefile()` (no `${}` / `{% %}` mixing)

### INF-041 · InjectFault state
`labels: area:sfn, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-040`

- [ ] `sqs:sendMessage` to `${faults_queue_url}` with the FAULT body from §7 (`sentAt` via `$now()`)
- [ ] `Catch States.ALL` → assign `reason = ERROR` → `MarkFailed`

### INF-042 · WaitForFix state (AWAIT_FIX + task token)
`labels: area:sfn, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-041`

- [ ] As in §6.1: `sqs:sendMessage.waitForTaskToken` to `user-actions.fifo`, group `$sessionId`, dedup `<sessionId>:await-fix`, `TimeoutSeconds = $maxResolveSeconds`
- [ ] Catches `States.Timeout` → TIMEOUT, `Abandoned` → ABANDONED, `States.ALL` → ERROR

### INF-043 · PersistResolved state
`labels: area:sfn, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-042`

- [ ] `dynamodb:updateItem` on `Sessions`: `state = RESOLVED`, score fields from §6.3, `ended_at`; condition `state = INCIDENT_ACTIVE`
- [ ] Attribute names agreed with the backend item shape (backend §7.1)
- [ ] `Catch States.ALL` → `MarkFailed`

### INF-044 · MarkFailed state
`labels: area:sfn, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-040`

- [ ] `dynamodb:updateItem`: `state = FAILED`, `failure_reason = $reason`, `ended_at`; condition `state IN (STARTING, INCIDENT_ACTIVE)`
- [ ] A failed condition still continues to `NotifyEndedFailed` (every path must send `SESSION_ENDED`)

### INF-045 · NotifyEnded and NotifyEndedFailed states
`labels: area:sfn, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-043, INF-044`

- [ ] `SESSION_ENDED` to `user-actions.fifo`, dedup `<sessionId>:ended`; `RESOLVED` → `Succeed`, `FAILED` + reason → `Fail`
- [ ] Every Task state reaches one of them (CONV §3)

### INF-046 · Spike O-03: JSONata TimeoutSeconds + FIFO arguments with TestState
`labels: area:sfn, type:spike` · `milestone: M2 · Orchestration` · `depends: INF-042, INF-035`

- [ ] Run TestState on `WaitForFix` in the lab; confirm `TimeoutSeconds` as a JSONata expression and `MessageGroupId`/`MessageDeduplicationId` work
- [ ] Record the result in DECISIONS (close O-03)

### INF-047 · make sfn-test: TestState checks for each state
`labels: area:sfn, area:ops, type:task` · `milestone: M2 · Orchestration` · `depends: INF-045, INF-035`

- [ ] Script calls `aws stepfunctions test-state` per state with fixture inputs in `statemachines/tests/`
- [ ] Covers the happy path and the TIMEOUT / ABANDONED / ERROR branches

### INF-048 · make sfn-smoke: one end-to-end execution in the lab
`labels: area:sfn, area:ops, type:task` · `milestone: M2 · Orchestration` · `depends: INF-047`

- [ ] Starts an execution with a short timeout, reads `faults` and `user-actions.fifo`, calls `SendTaskSuccess` with a fake §6.3 payload, checks the DynamoDB item and `SESSION_ENDED`
- [ ] Cleans up the test item

### INF-049 · Sync the state machine to the backend's local copy
`labels: area:sfn, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-045`

- [ ] PR in `oncall-training-backend` updating `local/statemachine.asl.json` (§14); a note in ARCHITECTURE that every ASL change needs this

---

## 5. Cluster stack (M1–M2)

### INF-050 · Cluster stack scaffold
`labels: area:terraform, stack:cluster, type:task` · `milestone: M1 · EKS up` · `depends: INF-016, INF-025`

- [ ] Standard files; S3 backend; default tags `Stack=cluster`; LabRole data source
- [ ] `terraform_remote_state "foundation"`
- [ ] Variables with validation: `node_instance_type` (t3/t4g up to large), `node_count`, `kubernetes_version`

### INF-051 · VPC and internet gateway
`labels: area:terraform, stack:cluster, type:task` · `milestone: M1 · EKS up` · `depends: INF-050`

- [ ] VPC `10.20.0.0/16` with DNS hostnames/support, IGW, `Name` tags
- [ ] Plain resources or the VPC module with all IAM-creating options off (if the module: add a decision entry, CONV §1.1)

### INF-052 · Public subnets and route table
`labels: area:terraform, stack:cluster, type:task` · `milestone: M1 · EKS up` · `depends: INF-051`

- [ ] `10.20.0.0/20` (us-east-1a), `10.20.16.0/20` (us-east-1b), `map_public_ip_on_launch`, tag `kubernetes.io/role/elb=1`
- [ ] Route table with `0.0.0.0/0 → IGW`; **no NAT**

### INF-053 · Private subnets for ElastiCache
`labels: area:terraform, stack:cluster, type:task` · `milestone: M2 · Orchestration` · `depends: INF-051`

- [ ] `10.20.128.0/24`, `10.20.129.0/24` with a route table that has no internet route

### INF-054 · EKS cluster
`labels: area:terraform, stack:cluster, type:task, billable` · `milestone: M1 · EKS up` · `depends: INF-052`

- [ ] `aws_eks_cluster` `oncall-training`: role LabRole, current standard-support version, `authentication_mode = "API"`, `bootstrap_cluster_creator_admin_permissions = true`, public endpoint, control-plane logging off
- [ ] Outputs `cluster_name`, `cluster_endpoint`

### INF-055 · EKS access entry for the lab principal
`labels: area:terraform, stack:cluster, type:task` · `milestone: M1 · EKS up` · `depends: INF-054`

- [ ] Access entry + `AmazonEKSClusterAdminPolicy` (cluster scope) for `arn:aws:iam::<acct>:role/voclabs`, built from the caller identity (not hardcoded)
- [ ] `kubectl` still works after a credential refresh

### INF-056 · Node launch template
`labels: area:terraform, stack:cluster, type:task` · `milestone: M1 · EKS up` · `depends: INF-054`

- [ ] IMDSv2 required, `http_put_response_hop_limit = 2`, 20 GB gp3 root volume, `Name` tag on instances

### INF-057 · Managed node group
`labels: area:terraform, stack:cluster, type:task, billable` · `milestone: M1 · EKS up` · `depends: INF-056`

- [ ] `default`: 2× `t3.medium`, `ON_DEMAND`, AL2023 x86_64, min 2 / desired 2 / max 3, public subnets, role LabRole, uses the launch template

### INF-058 · EKS add-ons: vpc-cni (network policy), coredns, kube-proxy
`labels: area:terraform, stack:cluster, type:task` · `milestone: M1 · EKS up` · `depends: INF-057`

- [ ] Versions pinned per Kubernetes version (variables or locals)
- [ ] `vpc-cni` with `configuration_values = {"enableNetworkPolicy": "true"}`

### INF-059 · ALB security group restricted to CloudFront
`labels: area:terraform, stack:cluster, type:task` · `milestone: M1 · EKS up` · `depends: INF-051`

- [ ] `oncall-training-alb`: inbound 80 only from the managed prefix list `com.amazonaws.global.cloudfront.origin-facing` (data source); every rule has a description
- [ ] Output `alb_security_group_id`

### INF-060 · Helm provider and AWS Load Balancer Controller release
`labels: area:terraform, stack:cluster, type:task` · `milestone: M1 · EKS up` · `depends: INF-058`

- [ ] Helm provider authenticated with `aws_eks_cluster_auth`
- [ ] `helm_release` `aws-load-balancer-controller` in `kube-system`, chart version pinned, `clusterName`, `region`, `vpcId` set, no service account annotation

### INF-061 · ElastiCache subnet group and security group
`labels: area:terraform, stack:cluster, type:task` · `milestone: M2 · Orchestration` · `depends: INF-053, INF-054`

- [ ] Subnet group on the private subnets
- [ ] SG: 6379 only from the EKS cluster security group; rule described

### INF-062 · ElastiCache Valkey replication group
`labels: area:terraform, stack:cluster, type:task, billable` · `milestone: M2 · Orchestration` · `depends: INF-061, INF-066`

- [ ] `oncall-training`: engine Valkey, smallest allowed node type (variable, from INF-066), 1 node, `transit_encryption_enabled = true`, no AUTH token
- [ ] Output `redis_endpoint` as `rediss://<host>:6379`

### INF-063 · Review cluster outputs against ARCHITECTURE §4
`labels: area:terraform, stack:cluster, type:task` · `milestone: M2 · Orchestration` · `depends: INF-062, INF-059`

- [ ] `cluster_name`, `cluster_endpoint`, `redis_endpoint`, `vpc_id`, `alb_security_group_id`, all with descriptions

---

## 6. Learner Lab spikes (O-01, O-04)

### INF-064 · Spike: EKS cluster and node group with LabRole
`labels: area:ops, stack:cluster, type:spike, billable, applies-aws` · `milestone: M1 · EKS up` · `depends: INF-057, INF-058`

- [ ] First `terraform apply` of the cluster stack; nodes `Ready`; access entry works
- [ ] Record the actual apply time and any lab restriction found in DECISIONS (O-01)
- [ ] Destroy at the end of the session

### INF-065 · Spike: Load Balancer Controller on the node role
`labels: area:ops, stack:cluster, type:spike, billable` · `milestone: M1 · EKS up` · `depends: INF-060, INF-064`

- [ ] A test Ingress creates an ALB with IP targets and the CloudFront-only SG
- [ ] If blocked: apply the D-07 fallback (`Service type: LoadBalancer`) and record a new decision

### INF-066 · Spike: smallest ElastiCache node type the lab allows
`labels: area:ops, type:spike` · `milestone: M2 · Orchestration` · `depends: INF-013`

- [ ] Check `cache.t3.micro` / `cache.t4g.micro` for Valkey in the lab (dry-run or a short-lived create); record the answer in DECISIONS

### INF-067 · Spike O-04: NetworkPolicies vs kubelet probes and ALB IP targets
`labels: area:ops, area:k8s, type:spike` · `milestone: M1 · EKS up` · `depends: INF-065, INF-075, INF-078, INF-086`

- [ ] With default-deny on: probes pass, ALB health checks pass, `app` → `mock` health works, `injector` → `mock` traffic is blocked
- [ ] Close O-04 in DECISIONS

---

## 7. Kubernetes manifests (M1)

### INF-068 · Kustomize skeleton and make k8s-validate
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-003`

- [ ] `kustomization.yaml` in `k8s/base` (including each area) and both overlays
- [ ] `make k8s-validate` runs `kustomize build … | kubeconform -strict -summary` for both overlays

### INF-069 · Namespaces app, injector, mock
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-068`

- [ ] `k8s/base/namespaces/namespace-*.yaml` with the standard labels (CONV §2)

### INF-070 · ServiceAccounts
`labels: area:k8s, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-069`

- [ ] `app/backend-api`, `app/backend-worker`, `injector/injector`
- [ ] `mock/default` (or a dedicated `mock` SA) with `automountServiceAccountToken: false`

### INF-071 · Role mock-reader + RoleBinding for backend-api
`labels: area:k8s, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-070`

- [ ] Exactly the rules in §5.2; no wildcards

### INF-072 · Role mock-operator + RoleBinding for backend-worker
`labels: area:k8s, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-070`

- [ ] mock-reader rules + `patch` on `deployments`, `deployments/scale`

### INF-073 · Role mock-injector + RoleBinding for injector
`labels: area:k8s, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-070`

- [ ] `get,list,delete` on `pods`; `get,patch` on `deployments`, `deployments/scale`

### INF-074 · RBAC check with kubectl auth can-i
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-071, INF-072, INF-073`

- [ ] `scripts/check-rbac.sh` asserts allowed and denied verbs per SA (e.g. the injector can't touch `app`, the api can't scale); runs on kind and EKS

### INF-075 · NetworkPolicy default-deny-ingress in all three namespaces
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-069`

- [ ] One policy per namespace, commented

### INF-076 · NetworkPolicy allow-alb-to-api
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-075`

- [ ] Ingress to `backend-api:3000` from the VPC CIDR `10.20.0.0/16`, with a comment

### INF-077 · NetworkPolicy allow-intra-mock
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-075`

- [ ] Ingress between mock pods on 8080

### INF-078 · NetworkPolicy allow-from-app in mock
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-075`

- [ ] Ingress to mock pods on 8080 from namespace `app` (namespace selector on `kubernetes.io/metadata.name`)

### INF-079 · Mock system Deployments (gateway, orders, worker-svc)
`labels: area:k8s, svc:mock, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-069, INF-070`

- [ ] Replicas 1 / 2 / 1 (scenario baseline), `ROLE` env, port 8080, liveness/readiness `/ping`
- [ ] Requests `50m`/`64Mi`, memory limit, full security context, `/tmp` emptyDir

### INF-080 · Mock system Services
`labels: area:k8s, svc:mock, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-079`

- [ ] ClusterIP `gateway`, `orders`, `worker-svc` on 8080 (names are part of `MOCK_HEALTH_URL_TEMPLATE`)

### INF-081 · Injector Deployment
`labels: area:k8s, svc:injector, type:task` · `milestone: M1 · EKS up` · `depends: INF-070`

- [ ] ×1, `strategy: Recreate`, SA `injector`, port 8080, probes `/healthz`, `envFrom` `oncall-config`, requests `100m`/`128Mi`, security context

### INF-082 · Backend api Deployment and Service
`labels: area:k8s, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-070`

- [ ] ×2, `node dist/api.js`, 3000, liveness `/healthz`, readiness `/readyz`, SA `backend-api`, `envFrom`
- [ ] Service ClusterIP 80 → 3000

### INF-083 · Backend worker Deployment
`labels: area:k8s, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-070`

- [ ] ×1, `Recreate`, `node dist/worker.js`, 3001, probes `/healthz`, SA `backend-worker`, `envFrom`

### INF-084 · scripts/render-config.sh
`labels: area:k8s, area:ops, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-025, INF-050`

- [ ] Reads `terraform output -json` from both stacks and writes `k8s/overlays/aws/config.env` with every key in §5.4 (backend + injector)
- [ ] Missing outputs (e.g. Redis before M2) fail clearly or are skipped with a warning

### INF-085 · aws overlay: images.env, image tags and ConfigMap generator
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-084, INF-079, INF-081, INF-082, INF-083`

- [ ] `images.env` (committed) holds `BACKEND_TAG`, `INJECTOR_TAG`, `MOCK_TAG`; Kustomize `images:` maps them to the ECR URLs
- [ ] `configMapGenerator` `oncall-config` from `config.env` in `app` and `injector` (hash suffix kept)

### INF-086 · aws overlay: backend-api Ingress
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-085, INF-059`

- [ ] `ingressClassName: alb` and the annotations in §5.1 (fixed name `oncall-training-api`, `target-type: ip`, SG from config, healthcheck `/healthz`, HTTP 80)

### INF-087 · local overlay for kind
`labels: area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-079, INF-081`

- [ ] Local image names, `imagePullPolicy: Never`, no Ingress, no backend Deployments (the backend runs on the host)
- [ ] Injector config points at LocalStack (`AWS_ENDPOINT_URL=http://host.docker.internal:4566`) and host Redis

---

## 8. Services workspace (M1)

### INF-088 · pnpm workspace and shared TypeScript tooling
`labels: area:svc, type:task` · `milestone: M1 · EKS up` · `depends: INF-003`

- [ ] Root `package.json`, `pnpm-workspace.yaml` (`services/*`), `tsconfig.base.json` (strict, ESM, NodeNext), ESLint + Prettier, Vitest
- [ ] Root scripts `lint`, `typecheck`, `test`, `build`

---

## 9. Mock system (M1)

### INF-089 · Mock system scaffold: env, logger, HTTP server, SIGTERM
`labels: area:svc, svc:mock, type:task` · `milestone: M1 · EKS up` · `depends: INF-088`

- [ ] zod env (`ROLE` = gateway | orders | worker-svc, `PORT=8080`), pino JSON logger with a short `msg`
- [ ] Graceful shutdown on `SIGTERM`

### INF-090 · Mock system GET /ping
`labels: area:svc, svc:mock, type:task` · `milestone: M1 · EKS up` · `depends: INF-089`

- [ ] Always 200 while the process is up; test

### INF-091 · Mock system GET /health dependency chain
`labels: area:svc, svc:mock, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-089`

- [ ] gateway → `orders /health` (800 ms), orders → `worker-svc /ping` (500 ms), worker-svc → 200
- [ ] 503 `{ status: "down", reason }` on failure; body includes `latencyMs`; downstream URLs from env
- [ ] Vitest: success, connection refused, timeout per role

### INF-092 · Mock system synthetic traffic from gateway
`labels: area:svc, svc:mock, type:task` · `milestone: M1 · EKS up` · `depends: INF-091`

- [ ] gateway calls `orders` every 500 ms; logs `info` on success, `error` with cause (`ECONNREFUSED …`, `timeout after 800ms`)
- [ ] Interval configurable; test for the log shape

### INF-093 · Mock system Dockerfile
`labels: area:svc, svc:mock, type:task` · `milestone: M1 · EKS up` · `depends: INF-089`

- [ ] Multi-stage `node:22-alpine`, `USER node`, `.dockerignore`, works with `readOnlyRootFilesystem`

### INF-094 · Mock system GET /metrics
`labels: area:svc, svc:mock, type:task` · `milestone: M3 · Data + e2e` · `depends: INF-092`

- [ ] `{ requests, errors, p50LatencyMs, p95LatencyMs }` since start; test for the percentile math

---

## 10. Injector (M1–M2)

### INF-095 · Injector scaffold: env, logger, /healthz, SIGTERM
`labels: area:svc, svc:injector, type:task` · `milestone: M1 · EKS up` · `depends: INF-088`

- [ ] zod env (`AWS_REGION`, `FAULTS_QUEUE_URL`, `SESSIONS_TABLE`, `REDIS_URL`, `MOCK_NAMESPACE`), pino with `faultId`/`sessionId` context
- [ ] `/healthz` on 8080; `SIGTERM` stops polling and finishes in-flight work

### INF-096 · Injector FAULT message schema and target validation
`labels: area:svc, svc:injector, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-095`

- [ ] zod schema for the FAULT message in §7
- [ ] Target check: namespace = `MOCK_NAMESPACE`, deployment in `gateway|orders|worker-svc`
- [ ] Vitest: valid, malformed, wrong namespace, unknown deployment, unknown type

### INF-097 · Injector Kubernetes gateway module
`labels: area:svc, svc:injector, type:task` · `milestone: M1 · EKS up` · `depends: INF-096`

- [ ] `scaleToZero(deployment)` patches `deployments/scale`; `deletePods(deployment)` deletes by the deployment's label selector
- [ ] The only module that talks to the Kubernetes API, always namespaced; tests with a fake client

### INF-098 · Injector SQS long-poll loop
`labels: area:svc, svc:injector, type:task` · `milestone: M1 · EKS up` · `depends: INF-096`

- [ ] `WaitTimeSeconds 20`; invalid messages logged and **not** deleted (left for the DLQ); deleted only after success
- [ ] Honors `AWS_ENDPOINT_URL`; tests with a fake SQS client

### INF-099 · Injector record step: DynamoDB INCIDENT_ACTIVE
`labels: area:svc, svc:injector, type:task, cross-repo` · `milestone: M1 · EKS up` · `depends: INF-095`

- [ ] Conditional `UpdateItem`: `STARTING` → `INCIDENT_ACTIVE`, `fault_injected_at`, `updated_at`; `ConditionalCheckFailed` treated as already applied
- [ ] Tests for both outcomes

### INF-100 · Injector record step: Redis FAULT_INJECTED event
`labels: area:svc, svc:injector, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-095`

- [ ] `RPUSH session:{id}:events` in the backend's event-line format + TTL refresh; TLS (`rediss://`) supported
- [ ] Format confirmed with JP (backend D-12); test with a fake Redis

### INF-101 · Injector handler: apply-then-record order and idempotency
`labels: area:svc, svc:injector, type:task` · `milestone: M1 · EKS up` · `depends: INF-097, INF-098, INF-099`

- [ ] Handler runs validate → apply → record → delete; a redelivered message is a no-op
- [ ] Vitest with fakes asserts the order and the idempotency

### INF-102 · Injector Dockerfile
`labels: area:svc, svc:injector, type:task` · `milestone: M1 · EKS up` · `depends: INF-095`

- [ ] Multi-stage `node:22-alpine`, `USER node`, `.dockerignore`

---

## 11. Local kind setup (M1)

### INF-103 · scripts/kind-up.sh: kind cluster with optional Calico
`labels: area:ops, area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-068`

- [ ] kind config for cluster `oncall-training`; `CALICO=1` disables the default CNI and installs a pinned Calico

### INF-104 · make kind-up / kind-down: build, load and apply
`labels: area:ops, area:k8s, type:task` · `milestone: M1 · EKS up` · `depends: INF-103, INF-087, INF-093, INF-102`

- [ ] Builds both images, `kind load docker-image`, applies `k8s/overlays/local`, waits for rollouts; `kind-down` deletes the cluster

### INF-105 · Local smoke test: fault in, system down, revive
`labels: area:ops, type:task` · `milestone: M1 · EKS up` · `depends: INF-104, INF-101`

- [ ] `scripts/local-smoke.sh` sends a FAULT to LocalStack `faults`, checks `orders` scaled to 0 and gateway `/health` = 503, scales back, checks 200

---

## 12. Lifecycle Makefile targets (M1–M2)

### INF-106 · make images: build and push injector and mock-system to ECR
`labels: area:ops, type:task` · `milestone: M1 · EKS up` · `depends: INF-024, INF-093, INF-102, INF-013`

- [ ] ECR login, tag = short git SHA, refuses to run on a dirty tree, prints the pushed tags

### INF-107 · make cluster-up (terraform + kubeconfig + manifests)
`labels: area:ops, stack:cluster, type:task, billable` · `milestone: M1 · EKS up` · `depends: INF-064, INF-084, INF-085`

- [ ] Steps 1–4 of §13.2, confirms before apply, prints the cost reminder

### INF-108 · scripts/update-api-origin.sh
`labels: area:ops, stack:foundation, type:task` · `milestone: M2 · Orchestration` · `depends: INF-030, INF-086`

- [ ] Waits for ALB `oncall-training-api`, then applies foundation with `-var api_origin_domain=<dns>`; called at the end of `cluster-up`
- [ ] `cluster-down` resets it to `api-origin.invalid`

### INF-109 · make cluster-down (Ingress first, then destroy)
`labels: area:ops, stack:cluster, type:task` · `milestone: M1 · EKS up` · `depends: INF-107`

- [ ] Deletes the Ingress, polls until the ALB and its controller-managed SGs are gone (with a timeout), then `terraform destroy`
- [ ] Prints that foundation stays up; exits non-zero if anything is left

### INF-110 · make status
`labels: area:ops, type:task` · `milestone: M1 · EKS up` · `depends: INF-107`

- [ ] Nodes, pods per namespace, ALB DNS, running image tags, and a "cluster is billing ~$0.25/h" reminder

### INF-111 · make deploy
`labels: area:ops, type:task` · `milestone: M1 · EKS up` · `depends: INF-085`

- [ ] Updates `images.env` with the given tags, re-applies the aws overlay, waits on `kubectl rollout status` for each changed Deployment
- [ ] Checks that each tag exists in ECR first

### INF-112 · make lint
`labels: area:ops, area:ci, type:task` · `milestone: M1 · EKS up` · `depends: INF-068, INF-088`

- [ ] `terraform fmt -check -recursive`, `validate` per stack (`-backend=false`), `tflint`, `make k8s-validate`, shellcheck, `pnpm lint typecheck test`

### INF-113 · Orphan check script for leftover billable resources
`labels: area:ops, type:task` · `milestone: M2 · Orchestration` · `depends: INF-109`

- [ ] `make orphans` lists ALBs, ENIs, EIPs/public IPv4 addresses, EKS clusters and ElastiCache clusters tagged or named `oncall-training` (read-only)

---

## 13. CI and workflows (M1–M2)

### INF-114 · ci.yml: Terraform fmt, validate and tflint
`labels: area:ci, type:task` · `milestone: M1 · EKS up` · `depends: INF-017, INF-050`

- [ ] Runs on PRs and pushes to `main`; no AWS credentials; actions pinned by SHA; `.tflint.hcl` with the AWS ruleset

### INF-115 · CI: forbidden IAM resource check
`labels: area:ci, type:task` · `milestone: M1 · EKS up` · `depends: INF-114`

- [ ] `scripts/check-forbidden-iam.sh` fails on any resource type in CONV §1.4 (including `aws_s3_bucket`, D-24); runs in `ci.yml` and `make lint`

### INF-116 · CI: kustomize build + kubeconform
`labels: area:ci, type:task` · `milestone: M1 · EKS up` · `depends: INF-114, INF-068`

- [ ] Both overlays build and validate (with a dummy `config.env` for the aws overlay)

### INF-117 · CI: pnpm lint, typecheck, test and docker build
`labels: area:ci, type:task` · `milestone: M1 · EKS up` · `depends: INF-114, INF-088`

- [ ] pnpm cache; both images build without pushing

### INF-118 · CI: shellcheck
`labels: area:ci, type:task` · `milestone: M1 · EKS up` · `depends: INF-114`

- [ ] All `scripts/*.sh` pass

### INF-119 · CI: checkov (soft-fail)
`labels: area:ci, type:task` · `milestone: M2 · Orchestration` · `depends: INF-114`

- [ ] Runs on `terraform/` and `k8s/`, reports without failing the build

### INF-120 · images.yml: build and push on merge
`labels: area:ci, type:task` · `milestone: M1 · EKS up` · `depends: INF-106, INF-013`

- [ ] Triggers on `main` with paths `services/**`, plus manual; credential check first; calls `make images`

### INF-121 · cluster.yml: manual up/down
`labels: area:ci, type:task, billable` · `milestone: M2 · Orchestration` · `depends: INF-107, INF-109`

- [ ] Input `action: up | down`, runs `make cluster-<action> CONFIRM=yes`, one `concurrency` group, credential check first

### INF-122 · deploy.yml: roll out tags and commit images.env
`labels: area:ci, type:task` · `milestone: M2 · Orchestration` · `depends: INF-111`

- [ ] Inputs `backend_tag`, `injector_tag`, `mock_tag`; runs `make deploy`; commits `images.env` back to `main`

---

## 14. Integration milestones (M1–M3)

### INF-123 · Deliverable Oct 29: workloads on EKS, injector kills, system revived
`labels: area:ops, type:task, billable` · `milestone: M1 · EKS up` · `depends: INF-107, INF-111, INF-067, INF-074`

- [ ] backend-api, backend-worker, injector and the mock system run in their namespaces
- [ ] A FAULT sent by hand to `faults` takes `orders` down; scaling back restores `/health`
- [ ] Demo steps written down; `make cluster-down` afterwards

### INF-124 · Spike O-02: does the injector have to revive the service?
`labels: area:sfn, type:spike, cross-repo` · `milestone: M1 · EKS up` · `depends: —`

- [ ] Ask the professor; if yes, open issues for `RESTORE_BASELINE` (injector + state machine end path); record the decision

### INF-125 · Verify ElastiCache TLS from the app namespace
`labels: area:ops, type:task` · `milestone: M2 · Orchestration` · `depends: INF-062, INF-084`

- [ ] A temporary pod in `app` connects with `rediss://` and runs `PING`; the injector writes events

### INF-126 · Verify CloudFront → ALB → backend-api
`labels: area:ops, type:task` · `milestone: M2 · Orchestration` · `depends: INF-108, INF-029`

- [ ] `https://<cloudfront>/api/healthz` (or the backend health route) returns 200; a direct request to the ALB is refused
- [ ] The SPA serves deep links (`/some/route` → `index.html`), API 404s stay 404

### INF-127 · Deliverable Nov 19: state machine drives a full session on EKS
`labels: area:ops, area:sfn, type:task, cross-repo` · `milestone: M2 · Orchestration` · `depends: INF-048, INF-123, INF-125`

- [ ] Backend `StartExecution` → fault injected → `AWAIT_FIX` received by the worker → `SendTaskSuccess` → RESOLVED + `SESSION_ENDED`
- [ ] TIMEOUT path checked once with a short `maxResolveSeconds`

### INF-128 · Deliverable Nov 26: e2e happy path on the deployed stack
`labels: area:ops, type:task, cross-repo` · `milestone: M3 · Data + e2e` · `depends: INF-127, INF-034, INF-038, INF-126`

- [ ] e2e user logs in through Cognito, completes a scenario, logs land in S3, the Athena-backed charts load
- [ ] Test steps documented

---

## 15. Polish and documentation (M4)

### INF-129 · Update ARCHITECTURE: drop "(planned)", record real versions
`labels: area:docs, type:task` · `milestone: M4 · Polish` · `depends: INF-128`

- [ ] Kubernetes, add-on, chart and provider versions; any change found during the spikes

### INF-130 · Record decision entries for choices made during build
`labels: area:docs, type:task` · `milestone: M4 · Polish` · `depends: INF-128`

- [ ] VPC module (if used), Calico version, Helm chart version, ElastiCache node type, spike results (O-01, O-03, O-04, O-02)

### INF-131 · Troubleshooting runbook
`labels: area:docs, type:task` · `milestone: M4 · Polish` · `depends: INF-109`

- [ ] `docs/RUNBOOK.md`: expired creds, orphaned ALB blocking VPC destroy, stuck `terraform` lock file, nodes not joining, pods `ImagePullBackOff`, `/api` 502 after `cluster-up`

### INF-132 · Triage checkov findings
`labels: area:terraform, area:k8s, type:task` · `milestone: M4 · Polish` · `depends: INF-119`

- [ ] Each finding fixed or suppressed inline with a reason

### INF-133 · Dependabot for GitHub Actions, Terraform providers and npm
`labels: area:ci, type:task` · `milestone: M4 · Polish` · `depends: INF-117`

- [ ] `.github/dependabot.yml`, weekly, grouped; SHA-pinned actions stay pinned

### INF-134 · README polish for the CV
`labels: area:docs, type:task` · `milestone: M4 · Polish` · `depends: INF-128`

- [ ] Architecture diagram, CI badge, what each part demonstrates, cost numbers, link to the decisions log, a short demo GIF or screenshots

### INF-135 · Cost report from the course
`labels: area:docs, area:ops, type:task` · `milestone: M4 · Polish` · `depends: INF-128`

- [ ] Real spend from the lab budget vs the estimate in §13.5, added to DECISIONS or the README

### INF-136 · Stretch (F-10): nightly cluster-down workflow
`labels: area:ci, type:task` · `milestone: M4 · Polish` · `depends: INF-121`

- [ ] Scheduled `cluster.yml` run with `action: down` (only works while lab creds are fresh; document that limit). Needs a team OK (out of MVP scope)

### INF-137 · End-of-course teardown checklist
`labels: area:ops, area:docs, type:task` · `milestone: M4 · Polish` · `depends: INF-128`

- [ ] Documented order to remove everything (cluster → foundation with `prevent_destroy` lifted → state bucket), plus what to export first (session data, screenshots)
