# Decisions, Limitations and Future Work

What we decided for the infrastructure, why, what we gave up, and what we'd do with more time or a real AWS account.
Add a new entry whenever something is decided or changed; don't rewrite history. If a decision is replaced, mark it **Superseded by D-xx**.

**Status values:**
- **Decided**: settled.
- **Proposed**: our preferred option, but it needs another repo's owner to agree.
- **Superseded**: replaced by a later decision.

---

## 1. Decision log

| ID | Date | Decision | Status |
|---|---|---|---|
| D-01 | 2026-10-22 | The infra repo owns Terraform, all k8s manifests, the state machine, the injector and the mock system | Decided |
| D-02 | 2026-10-22 | Two Terraform stacks (`foundation`, `cluster`) + `bootstrap`; S3 state with native lock file | Decided |
| D-03 | 2026-10-22 | `LabRole` for every role; plain EKS resources instead of the community EKS module | Decided (forced by Learner Lab) |
| D-04 | 2026-10-22 | Nodes and ALB in public subnets, no NAT; ElastiCache in private subnets | Decided |
| D-05 | 2026-10-22 | EKS managed node group: 2× t3.medium On-Demand, IMDS hop limit 2, access entries | Decided |
| D-06 | 2026-10-22 | NetworkPolicies enforced by the Amazon VPC CNI | Decided |
| D-07 | 2026-10-22 | AWS Load Balancer Controller → ALB, ALB restricted to CloudFront's prefix list | Decided |
| D-08 | 2026-10-22 | CloudFront lives in `foundation`; its API origin is updated after each `cluster-up` | Decided |
| D-09 | 2026-10-22 | ElastiCache Valkey, single small node, in-transit TLS, no AUTH token | Decided |
| D-10 | 2026-10-22 | Kustomize base + `aws`/`local` overlays; config generated from Terraform outputs | Decided |
| D-11 | 2026-10-22 | Namespaced Roles in `mock` bound to service accounts in other namespaces; no ClusterRoles | Decided |
| D-12 | 2026-10-22 | Step Functions Standard workflow written in JSONata | Decided |
| D-13 | 2026-10-22 | `WaitForFix` uses `sqs:sendMessage.waitForTaskToken` (`AWAIT_FIX`), not DynamoDB | Decided (**corrects backend D-09**) |
| D-14 | 2026-10-22 | Accepted the cross-repo proposals: backend D-11, D-12, D-13 and frontend D-14 | Decided |
| D-15 | 2026-10-22 | `faults` is a standard queue; `user-actions` is FIFO | Decided |
| D-16 | 2026-10-22 | Injector and mock system in TypeScript (pnpm workspace) | Decided |
| D-17 | 2026-10-22 | Mock system: `gateway → orders → worker-svc`, probes on `/ping`, `/health` reflects downstream | Decided |
| D-18 | 2026-10-22 | Image rollouts happen from this repo (`make deploy` / `deploy.yml`), tags pinned in `images.env` | Decided (answers backend O-03) |
| D-19 | 2026-10-22 | Lifecycle through a Makefile; GitHub workflows call the same targets; Learner Lab credentials as secrets | Decided |
| D-20 | 2026-10-22 | `cluster-down` deletes the Ingress and waits for the ALB before `terraform destroy` | Decided |
| D-21 | 2026-10-22 | Glue table with partition projection; Athena workgroup with a 100 MB scan limit | Decided |
| D-22 | 2026-10-22 | The e2e Cognito user is created by a script, not Terraform | Decided (answers frontend O-04) |
| D-23 | 2026-10-22 | Docs written in English | Decided |
| D-24 | 2026-10-27 | S3 buckets use `awscc_s3_bucket` (Cloud Control), not `aws_s3_bucket` | Decided (forced by Learner Lab) |
| D-25 | 2026-10-27 | Nov 5 MVP: one incident loop on EKS without Step Functions, ElastiCache, Cognito or CloudFront | Decided (temporary until Nov 19) |
| D-26 | 2026-11-01 | EKS access: one explicit access entry for the lab role; no automatic creator entry | Decided |
| D-27 | 2026-11-01 | Image tags and account-specific values reach the aws overlay through Kustomize replacements | Decided |
| D-28 | 2026-11-05 | No API Gateway: CloudFront is the edge, the ALB routes to the pods | Decided |

---

## 2. Decisions in detail

### D-01 · What the infra repo owns
**Why:** everything that runs in or configures the cluster changes together (RBAC, NetworkPolicies, the injector's permissions, the mock system's names). The injector and mock system exist only to exercise the infrastructure. Keeping all manifests here, including the backend's, gives one place to see and apply the whole cluster.
**Trade-off:** a backend change that needs a new env var or permission is a two-repo change. Mitigated by the contract tables in ARCHITECTURE §5–7.

### D-02 · Two stacks + bootstrap
**Why:** the cluster stack (EKS, ALB, ElastiCache, IPv4) bills by the hour and must be destroyed after every work session, while data and users must survive. Separate stacks make `terraform destroy` on the cluster safe by construction. S3 native locking (Terraform ≥ 1.10) avoids a DynamoDB lock table.
**Bootstrap** keeps local state because something has to create the state bucket; it's one resource and can be re-imported.

### D-03 · LabRole and plain resources
**Why:** the Learner Lab can't create IAM roles, policies or OIDC providers. The community EKS module creates several of these by default (cluster role, node role, KMS key policy, IRSA provider). Turning them all off is fragile, and the module hides what it creates. Plain `aws_eks_cluster`, `aws_eks_node_group` and `aws_eks_addon` resources are a few dozen lines and fully visible.
**Trade-off:** more lines than a module call. In a real account we'd likely use the module (F-01).

### D-04 · Public subnets, no NAT
**Why:** a NAT gateway costs about $1/day plus data, and adds nothing to the lab's security model (we can't scope IAM anyway). Nodes get public IPs, but security groups only allow traffic from inside the VPC and the control plane. ElastiCache stays in private subnets with no internet route.
**Trade-off:** not production practice (L-03); nodes are reachable on the internet at the IP level, protected by security groups.

### D-05 · Node group sizing and settings
**Why:** 2× t3.medium fits all pods (api×2, worker, injector, mock×4 pods, LB controller×2, CoreDNS×2, plus DaemonSets) within the VPC CNI's 17-pods-per-node limit, spread over 2 AZs, at about $0.08/h. On-Demand because the lab has no Spot. **Hop limit 2** is required for containers to reach IMDS and use the node role (D-17 in the backend). **Access entries** (API auth mode) avoid the old `aws-auth` ConfigMap and let us grant the lab principal admin explicitly.

### D-06 · VPC CNI network policies
**Why:** NetworkPolicies are a course requirement ("separated by namespaces + NetworkPolicies"). The VPC CNI can enforce them natively with one add-on setting, so there's no extra CNI (Calico) to run on EKS. Locally, kind needs Calico to enforce them.

### D-07 · ALB via the Load Balancer Controller, CloudFront-only
**Why:** an Ingress gives HTTP health checks on `/healthz`, IP targets (direct to pods) and a stable name. The controller runs on the node role, so no IRSA is needed. The ALB's security group only accepts CloudFront's origin-facing IP ranges, so the API can't be called around CloudFront.
**Fallback:** if the controller is blocked in the lab (O-01), use a `Service type: LoadBalancer` (NLB) with the same security group idea.

### D-08 · CloudFront in foundation
**Why:** the SPA must stay online (and keep its URL, which is registered in Cognito) even when the cluster is down. The ALB is created by the controller and changes on every `cluster-up`, so `update-api-origin.sh` re-applies foundation with the new ALB DNS name.
**Trade-off:** a few minutes after `cluster-up` before `/api/*` works through CloudFront, and `/api/*` returns 502 while the cluster is down (L-02).

### D-09 · ElastiCache Valkey, single node, TLS
**Why:** ElastiCache is a course requirement. Valkey is the cheaper, open-source Redis-compatible engine. One node is enough for a cache plus a lock. In-transit TLS costs nothing extra; the backend uses `rediss://`. No AUTH token, because access is limited by the security group and a token would need secret handling.
**Trade-off:** no failover (L-05).

### D-10 · Kustomize, config from outputs
**Why:** plain YAML that `kubectl` understands, with small overlays for kind vs. AWS. Rendering `config.env` from Terraform outputs means no endpoint or ARN is typed by hand. The ConfigMap hash suffix restarts pods when config changes.
**Alternatives considered:** Helm (templating we don't need); the Terraform kubernetes provider (couples app rollout to the cluster stack's lifecycle and is slow to iterate).

### D-11 · RBAC in the `mock` namespace
**Why:** the permissions are about what can be done **to** the mock system, so the Roles live there and are bound to the api, worker and injector service accounts in their own namespaces. Namespaced Roles mean no workload can touch `app`, `injector` or `kube-system` through the Kubernetes API.

### D-12 · Standard workflow, JSONata
**Why:** Standard workflows support `.waitForTaskToken` and runs up to a year, and are billed per state transition (a session is about 10 transitions). JSONata makes data shaping shorter and clearer than JSONPath's `Parameters`/`ResultPath`/`OutputPath`, and it has `$now()` for timestamps.

### D-13 · Wait for the fix through SQS, not DynamoDB
**Why:** Step Functions' DynamoDB integration only supports request-response. It **can't** pause for a task token, so the backend's original plan (backend D-09: "`dynamodb:updateItem.waitForTaskToken`") isn't possible. SQS `sendMessage.waitForTaskToken` is supported. The state machine sends `AWAIT_FIX` with the token to `user-actions.fifo` (same FIFO group as the user's actions), and the worker stores the token on the session item.
**Alternatives considered:** a Lambda that stores the token (another deploy unit, also on LabRole).
**Action:** the backend docs must be updated (task token written by the worker; new `AWAIT_FIX` system message).

### D-14 · Cross-repo proposals accepted
- Backend D-11: `SESSION_ENDED` on every terminal path.
- Backend D-12: the injector marks the session `INCIDENT_ACTIVE` and appends `FAULT_INJECTED`.
- Backend D-13: FIFO `user-actions`.
- Frontend D-14: CloudFront Function SPA fallback, no custom error responses.

All are implemented as described in ARCHITECTURE §6–7 and §11.

### D-15 · Standard `faults`, FIFO `user-actions`
**Why:** there's one fault per session and the injector is idempotent, so FIFO ordering adds nothing to `faults`. `user-actions` carries ordered user actions plus system messages for the same session, so FIFO per `sessionId` matters there.

### D-16 · TypeScript for the injector and mock system
**Why:** it's the same language, tooling and Kubernetes client as the backend, so both teammates can work on either. The services are tiny; Go's smaller images don't matter at this scale.

### D-17 · Mock system design
**Why:** a three-hop chain lets a fault in the middle (`orders`) show up as a symptom at the edge (`gateway` errors), so the user has to diagnose rather than just read which pod is red. Probes use `/ping` (process alive) so Kubernetes doesn't restart healthy upstream pods when a downstream fails; `/health` reports the dependency chain for the dashboard. Synthetic traffic produces realistic error logs.

### D-18 · Rollouts from the infra repo
**Why:** the manifests live here, so applying them belongs here too. `images.env` committed in git is a record of what's running. App repos only build and push images.

### D-19 · Makefile + workflows
**Why:** make targets give fast feedback from a laptop with fresh lab credentials. Workflows calling the same targets make runs reproducible and visible to both teammates. Learner Lab credentials must be pasted into GitHub secrets each session (`make creds` automates that), because GitHub OIDC needs IAM resources we can't create.

### D-20 · Delete the Ingress before destroying the cluster
**Why:** the ALB is created by the controller, not by Terraform. If the cluster is destroyed first, the ALB and its security group rules are orphaned. They keep billing, and they block the VPC from being deleted.

### D-21 · Partition projection and scan limit
**Why:** projection computes partitions from the S3 path pattern, so there's no crawler or `MSCK REPAIR` after each day's logs. The 100 MB per-query cutoff stops a bad query from scanning everything.

### D-22 · e2e user via script
**Why:** creating a Cognito user in Terraform would put its password in the state file. A script that reads the password from an env var keeps it out of git and state.

### D-23 · English docs
**Why:** they match the other repos, work best for the CV, and are what agents handle most reliably.

### D-24 · S3 buckets through the awscc provider
**Why:** the Learner Lab's service control policy denies `s3:GetBucketObjectLockConfiguration`. The `aws` provider's `aws_s3_bucket` reads the object lock configuration on every refresh and treats AccessDenied as fatal, so any `aws_s3_bucket` fails right after it's created and on every plan after that. This was found on the first bootstrap apply (2026-10-27); it's the only S3 bucket read the policy denies, and no provider version from 5.80 to 6.70 tolerates it. `awscc_s3_bucket` reads the bucket through the Cloud Control API, which works, and covers versioning, encryption, public access block, lifecycle and tags in one resource.
**Scope:** only the bucket itself. Everything else, including `aws_s3_bucket_policy` and `data "aws_s3_bucket"`, stays on the `aws` provider. `awscc` has no `default_tags`, so each stack builds `local.awscc_tags` from the same tag map.
**Alternatives considered:** creating the buckets with the AWS CLI and referencing them with data sources (breaks "all AWS resources go through Terraform"); asking AWS Academy to relax the policy (not in our control).

### D-25 · Nov 5 MVP shortcuts
**Why:** the course added a first rough MVP, due Thu Nov 5, with at least one working flow. The incident loop (start → fault → fix → resolved) is the product, and it reuses the Oct 29 work (EKS, mock system, injector). Step Functions, ElastiCache, Cognito and CloudFront each take days of work and lab testing, and none of them is needed to show the loop.
**What changes until Nov 19** (details in ARCHITECTURE §15):
- The backend api sends `FAULT` to `faults` itself, and the worker writes `RESOLVED`/`FAILED` (backend D-24, `ORCHESTRATION_MODE=direct`).
- No ElastiCache: no global lock (one demo user); the dashboard is built on request.
- No Cognito: dev auth in the backend (`AUTH_MODE=dev`, `ALLOW_DEV_AUTH=true`) and the frontend.
- No CloudFront: the SPA runs with `pnpm dev`, and its Vite proxy sends `/api` to the ALB (frontend D-18). The ALB security group allows only the demo machines' IPs (INF-138) instead of CloudFront's prefix list (INF-059).
- NetworkPolicies, most CI and kind move to M2.
**Kept:** the contracts (FAULT message, session item, API shapes) don't change, so M2 swaps implementations instead of rewriting them.
**Alternatives considered:** demoing on kind (doesn't match the course's EKS story); calling the ALB from the browser with CORS (the backend and frontend forbid CORS).

### D-26 · One explicit EKS access entry for the lab role
**Why:** in the lab, the principal that creates the cluster *is* the `voclabs` role. With `bootstrap_cluster_creator_admin_permissions = true`, EKS creates an access entry for it, and the explicit `aws_eks_access_entry` for the same role then fails with "already exists". So the automatic entry is off and Terraform manages the only one. The role ARN is parsed from the caller ARN (`arn:aws:sts::<acct>:assumed-role/voclabs/<session>` → `arn:aws:iam::<acct>:role/voclabs`), so nothing is hardcoded and it works in any lab account. Not `data "aws_iam_session_context"`: it calls `iam:GetRole`, which the lab explicitly denies on `voclabs` (found on account 881462672893, 2026-11-04; `GetRole` on `LabRole` is allowed). The ARN of the role doesn't change when credentials rotate, so `kubectl` keeps working after `make creds`.
**Also:** `upgrade_policy { support_type = "STANDARD" }`, so the cluster never falls into extended support, which bills about 6× the standard control-plane rate.
**Trade-off:** whoever applies the cluster stack must be the lab role; a different principal (e.g. a personal IAM user outside the lab) would get admin instead. Not a concern in the lab.

### D-27 · Kustomize replacements for tags, registry and ALB security group
**Why:** the aws overlay needs the ECR registry (contains the account id) and the ALB security group id, which must not be committed (AGENTS §4), plus the image tags, which should be committed so the running versions are visible in git (ARCHITECTURE §13.4). Kustomize's `images:` only takes literals. Instead, base images are `registry.invalid/oncall-training/<repo>:unset`, and `replacements` fill the tag from `images.env` (committed) and the registry and security group from `cluster.env` (gitignored, written by `render-config.sh`). Both inputs are `local-config` ConfigMaps, so they never reach the cluster.
**Backend replicas:** the overlay sets `backend-api` and `backend-worker` to 0 replicas until the backend's first image is in ECR (backend #27/#29). The change that sets `BACKEND_TAG` removes that block.
**Alternatives considered:** `kustomize edit set image` at deploy time (writes the account id into a committed file); `envsubst` over the build output (bypasses Kustomize and its validation).


### D-28 · No API Gateway
**Why:** an ALB and API Gateway overlap only at the edges (TLS, path routing, basic auth). The ALB is a load balancer: it routes to the pods, health-checks them and integrates with Kubernetes through the Ingress. API Gateway is an API management product: API keys, usage plans, per-client throttling, request validation, authorizers. Our requirements (one SPA client, one backend, the API on the same domain as the SPA, HTTPS, the ALB reachable only from CloudFront) are covered by CloudFront (edge, HTTPS, one domain, no CORS), the ALB (routing, health checks) and the backend (Cognito token validation).
**Not interchangeable:** API Gateway can't reach pods inside the VPC by itself; it needs a VPC Link to a load balancer. On EKS it would sit in front of the ALB, not replace it, adding a hop (CloudFront → API Gateway → VPC Link → ALB → pod), per-request cost, a 29 s default integration timeout on REST APIs, and a second place for routing rules.
**When to revisit:** several API consumers (partners, mobile apps) needing keys, quotas or usage tracking; a monetized or rate-limited public API; Lambda backends; one facade with uniform policies over many services. On Kubernetes, also weigh an in-cluster gateway (Envoy Gateway, Kong, the Gateway API).
---

## 3. Current limitations

| ID | Limitation | Impact | Mitigation now |
|---|---|---|---|
| L-01 | No per-workload IAM (all pods use LabRole) | Any pod can call any AWS API LabRole allows | Namespaces, RBAC, NetworkPolicies; only our images run in the cluster |
| L-02 | CloudFront → ALB is plain HTTP; API origin updates after `cluster-up` | Traffic between CloudFront and the ALB isn't encrypted; `/api` returns 502 while the cluster is down | ALB only accepts CloudFront IP ranges; documented in the lab routine |
| L-03 | Nodes in public subnets, no NAT | Not production practice | Tight security groups; no SSH; IMDSv2 required |
| L-04 | `cluster-up` takes about 20 min | Slow start to each work session | Develop on kind + LocalStack; bring EKS up only to integrate or demo |
| L-05 | Single ElastiCache node, single worker, single injector | No failover; a restart pauses sessions for seconds | Kubernetes restarts pods; backend tolerates a Redis restart (backend L-03/L-04) |
| L-06 | Lab credentials expire each session | Workflows fail until `make creds` runs | The credential check gives a clear error |
| L-07 | Lab budget is finite; the cluster costs about $6/day if left up | Risk of losing the account | `make cluster-down` routine; budget check at session start |
| L-08 | State bucket and shared environment exist only in Ian's lab account | JP can't apply to the shared environment | JP can stand up a personal copy with the same code in his lab |
| L-09 | No custom domain or certificate | `*.cloudfront.net` URL | Fine for the course |
| L-10 | No metrics or alerting stack | Debugging relies on `kubectl logs` and CloudWatch (Step Functions) | `make status`; JSON logs |
| L-11 | kind doesn't enforce NetworkPolicies by default | Local behavior can differ from EKS | Optional Calico in `make kind-up`; policies tested on EKS |
| L-12 | The lab's SCP denies `s3:GetBucketObjectLockConfiguration` | `aws_s3_bucket` can't be used; buckets need a second provider (`awscc`) | D-24; CI rejects `aws_s3_bucket` (CONV §1.4) |
| L-13 | Until Nov 19 (MVP, D-25): dev auth, no global lock, ALB reachable over plain HTTP from the demo IPs | Anyone on a listed IP can act as any user; two sessions at once would conflict | ALB limited to the demo machines' IPs; one demo user; replaced in M2 |

---

## 4. Future improvements

| ID | Improvement | Helps |
|---|---|---|
| F-01 | Real account: IRSA or EKS Pod Identity with one least-privilege role per service account; GitHub OIDC deploy role; consider the community EKS module | L-01, L-06 |
| F-02 | Private node subnets + VPC endpoints (S3, DynamoDB, SQS, ECR, STS) instead of NAT | L-03 |
| F-03 | Custom domain + ACM certificate; HTTPS from CloudFront to the ALB; origin-verify secret header | L-02, L-09 |
| F-04 | Per-session mock namespaces (with ResourceQuota and cleanup) to allow concurrent sessions | Backend L-01 |
| F-05 | Prometheus + Grafana (or CloudWatch Container Insights) for the mock system; the dashboard could read real metrics | L-10, realism |
| F-06 | Chaos Mesh or Litmus for richer faults (latency, CPU stress, network partitions) | Scenario variety |
| F-07 | GitOps (Argo CD) instead of `make deploy` | Drift detection, audit |
| F-08 | Karpenter or Fargate for faster, cheaper capacity | L-04 |
| F-09 | ElastiCache with a replica (or Serverless) | L-05 |
| F-10 | Scheduled automatic `cluster-down` (e.g. a nightly workflow) as a cost guard | L-07 |
| F-11 | Separate environments (workspaces or directories per env) | Safer changes |

---

## 5. Open questions

| ID | Question | Owner | Blocks |
|---|---|---|---|
| O-01 | **Learner Lab smoke test:** EKS with LabRole as cluster and node role; LB controller working on the node role; the smallest allowed ElastiCache node type; Cognito managed login domain; CloudFront Functions; Step Functions logging with LabRole; VPC CNI network policy agent permissions | Ian | Everything in `cluster` |
| O-02 | The success criterion says the **injector** "kills and revives" a service. Today the user's fix and the backend worker's reset revive it. If the injector itself must revive it, add a `RESTORE_BASELINE` fault type sent by the state machine at the end (instead of the worker reset) | Ian (ask the professor) | State machine end path |
| O-03 | Does JSONata's `TimeoutSeconds` expression and `sqs:sendMessage.waitForTaskToken` with FIFO arguments (`MessageGroupId`, `MessageDeduplicationId`) work as written? Verify with TestState | Ian | `WaitForFix` |
| O-04 | Do the VPC CNI network policies allow kubelet probes and ALB IP-target traffic as expected (§5.3)? | Ian | NetworkPolicies |
| O-05 | Does LocalStack's Step Functions support `sqs:sendMessage.waitForTaskToken`, for the backend's local loop? | JP | Backend local full loop (backend O-02) |
