# Infra Architecture

Living document, and the source of truth for every AWS resource, Kubernetes object and cross-repo contract this repo owns.
Items marked **(planned)** aren't built yet. Items marked **(cross-repo)** are used by another repo; change them only together with that repo's owner.

## 1. Overview

```
                         ┌──────────────────────────── foundation (always on) ───────────────────────────┐
Browser ──► CloudFront ──┤ /*      → S3 site (OAC) + CloudFront Function "spa-rewrite"                    │
                         │ /api/*  → ALB origin (domain set after cluster-up)                             │
                         │ Cognito User Pool · DynamoDB Sessions · S3 files · SQS faults, user-actions.fifo │
                         │ Step Functions "scenario" · Glue table + Athena workgroup · ECR ×3              │
                         └───────────────────────────────────────────────────────────────────────────────┘
                         ┌──────────────────────────── cluster (destroy when idle) ──────────────────────┐
                         │ VPC (2 AZ) · public subnets: EKS nodes + ALB · private subnets: ElastiCache   │
                         │ EKS ── ns:app      backend-api ×2, backend-worker ×1                          │
                         │     ── ns:injector injector ×1                                                │
                         │     ── ns:mock     gateway ×1 → orders ×2 → worker-svc ×1                     │
                         │     ── kube-system aws-load-balancer-controller, coredns, aws-node (netpol)   │
                         │ ElastiCache Valkey (TLS)                                                      │
                         └───────────────────────────────────────────────────────────────────────────────┘
```

**Session flow** (who does what):

| Step | Actor | Mechanism |
|---|---|---|
| 1 | backend api | `StartExecution` with the input in §6.2 |
| 2 | state machine | waits `warmupSeconds`, sends a fault to `faults` |
| 3 | injector | applies the fault in ns `mock`, updates the session to `INCIDENT_ACTIVE` |
| 4 | state machine | sends `AWAIT_FIX` + task token to `user-actions.fifo` and waits (timeout = `maxResolveSeconds`) |
| 5 | backend worker | stores the token, applies user actions, detects resolution, calls `SendTaskSuccess` |
| 6 | state machine | persists the result in DynamoDB, sends `SESSION_ENDED` |
| 7 | backend worker | flushes logs to S3, resets the mock system, releases the lock |

## 2. Terraform layout and state

| Stack | Path | State key | Lifecycle |
|---|---|---|---|
| bootstrap | `terraform/bootstrap` | **local** (`terraform.tfstate`, gitignored; recreate with `import` if lost) | once per lab account |
| foundation | `terraform/foundation` | `s3://oncall-training-tfstate-<acct>/foundation.tfstate` | always on |
| cluster | `terraform/cluster` | `s3://oncall-training-tfstate-<acct>/cluster.tfstate` | up for work sessions, destroyed after |

- Backend: `backend "s3" { bucket, key, region = "us-east-1", use_lockfile = true, encrypt = true }`. Configured with `-backend-config=backend.hcl` (gitignored) so the account-specific bucket name isn't committed.
- **Dependencies:**
  - `cluster` reads `foundation` outputs through `terraform_remote_state` (queue URLs, table name, bucket names, Cognito IDs).
  - `foundation` takes **one** input from the cluster: `api_origin_domain` (the ALB DNS name), set by `scripts/update-api-origin.sh` after `cluster-up`. Default `"api-origin.invalid"` so CloudFront is valid while the cluster is down; `/api/*` returns 502 then.
- **Naming:** `local.name = "oncall-training"`. Globally unique names add the account id: `oncall-training-files-<acct>`. Every resource gets default tags through the provider:
  `Project=oncall-training`, `Owner=ian|jp`, `Env=lab`, `ManagedBy=terraform`, `Stack=foundation|cluster`.

## 3. Foundation resources (`terraform/foundation`)

| Resource | Name | Key settings |
|---|---|---|
| S3 files bucket | `oncall-training-files-<acct>` | Block public access, SSE-S3, versioning off; lifecycle: `athena-results/` expires after 7 days; prefixes `scenarios/`, `logs/`, `athena-results/` |
| S3 site bucket | `oncall-training-site-<acct>` | Block public access, SSE-S3; bucket policy allows `s3:GetObject` only from this CloudFront distribution (OAC, `AWS:SourceArn` condition) |
| DynamoDB | `Sessions` | On-demand, PITR on; PK `user_id` (S), SK `session_id` (S); GSI `Leaderboard` (PK `scenario_id` S, SK `score` N, projection ALL); deletion protection on |
| SQS | `oncall-training-faults` + `-faults-dlq` | Standard; visibility 60 s; retention 1 day; `maxReceiveCount = 3`; SSE-SQS |
| SQS | `oncall-training-user-actions.fifo` + `-user-actions-dlq.fifo` | FIFO, content-based dedup **off** (senders set `MessageDeduplicationId`); visibility 60 s; `maxReceiveCount = 3`; SSE-SQS |
| Step Functions | `oncall-training-scenario` | Standard; role = LabRole; definition from `statemachines/scenario.asl.json` via `templatefile()`; logging level `ERROR` to log group `/aws/states/oncall-training-scenario` (14-day retention) |
| Glue | database `oncall_training`, table `session_events` | §10.2 |
| Athena | workgroup `oncall-training` | Enforced output `s3://…files…/athena-results/`; `bytes_scanned_cutoff_per_query = 100 MB`; engine v3 |
| Cognito | user pool `oncall-training-users` | Email sign-in, self sign-up on, email verification; managed login domain `oncall-training-<acct>`; app client: public (no secret), auth code + PKCE, scopes `openid email profile`, refresh tokens on, access token 60 min; callback/logout URLs in §12 |
| ECR | `oncall-training/backend`, `oncall-training/injector`, `oncall-training/mock-system` | Immutable tags, scan on push, lifecycle: keep the last 15 images |
| CloudFront | distribution + OAC + Function `spa-rewrite` | §11 |

**Outputs** (consumed by the cluster stack, scripts and other repos' CI variables): `sessions_table`, `files_bucket`, `site_bucket`, `faults_queue_url`, `user_actions_queue_url`, `state_machine_arn`, `athena_workgroup`, `glue_database`, `cognito_user_pool_id`, `cognito_client_id`, `cognito_domain`, `cloudfront_domain`, `cloudfront_distribution_id`, `ecr_repository_urls`.

## 4. Cluster resources (`terraform/cluster`)

| Resource | Settings |
|---|---|
| VPC | `10.20.0.0/16`, 2 AZs (`us-east-1a`, `us-east-1b`); public subnets `10.20.0.0/20`, `10.20.16.0/20` (map public IP, tagged `kubernetes.io/role/elb=1`); private subnets `10.20.128.0/24`, `10.20.129.0/24` (no route to the internet); IGW; **no NAT** |
| EKS cluster | `oncall-training`; current EKS standard-support version; role = LabRole; `authentication_mode = "API"`; `bootstrap_cluster_creator_admin_permissions = true`; public endpoint; control-plane logging off (cost) |
| Access entries | Cluster admin policy for the lab principal (`arn:aws:iam::<acct>:role/voclabs`), so access survives credential rotation |
| Node group | `default`: **2× `t3.medium`**, `ON_DEMAND`, AL2023 x86_64, min 2 / desired 2 / max 3, public subnets, role = LabRole; launch template: IMDSv2 required, **`http_put_response_hop_limit = 2`** (so pods can use the node role), 20 GB gp3 |
| Add-ons | `vpc-cni` with `{"enableNetworkPolicy": "true"}`, `coredns`, `kube-proxy` (versions pinned per EKS version) |
| AWS Load Balancer Controller | `helm_release` (chart pinned) in `kube-system`; uses the node role (no service account annotation); `clusterName`, `region`, `vpcId` set explicitly |
| ALB security group | `oncall-training-alb`: inbound 80 **only from the CloudFront origin-facing managed prefix list** (`com.amazonaws.global.cloudfront.origin-facing`); attached through Ingress annotations |
| ElastiCache | Replication group `oncall-training`, engine **Valkey**, `cache.t3.micro` (or the smallest the lab allows), 1 node, private subnets, `transit_encryption_enabled = true`, no AUTH token; SG allows 6379 only from the EKS cluster/node security group |

**Outputs:** `cluster_name`, `cluster_endpoint`, `redis_endpoint` (→ `rediss://<host>:6379`), `vpc_id`, `alb_security_group_id`.

## 5. Kubernetes layout (`k8s/`)

### 5.1 Workloads

| Namespace | Workload | Kind / replicas | Image | Command | Ports / probes |
|---|---|---|---|---|---|
| `app` | `backend-api` | Deployment ×2 | `oncall-training/backend:<sha>` | `node dist/api.js` | 3000; liveness `/healthz`, readiness `/readyz` |
| `app` | `backend-worker` | Deployment ×1, **strategy `Recreate`** (never two workers) | same | `node dist/worker.js` | 3001; liveness/readiness `/healthz` |
| `injector` | `injector` | Deployment ×1, `Recreate` | `oncall-training/injector:<sha>` | default | 8080; `/healthz` |
| `mock` | `gateway` | Deployment ×1 | `oncall-training/mock-system:<sha>` | `ROLE=gateway` | 8080; liveness/readiness `/ping` |
| `mock` | `orders` | Deployment ×2 | same | `ROLE=orders` | same |
| `mock` | `worker-svc` | Deployment ×1 | same | `ROLE=worker-svc` | same |

- Every container: requests (`50m`/`64Mi` for mock, `100m`/`128Mi` for the others), memory limits, `runAsNonRoot`, `readOnlyRootFilesystem: true` (writable `emptyDir` at `/tmp`), `allowPrivilegeEscalation: false`, all capabilities dropped.
- Services: ClusterIP for `backend-api` (80 → 3000) and each mock service (8080). The DNS names `gateway.mock.svc.cluster.local` etc. are part of the backend's `MOCK_HEALTH_URL_TEMPLATE` (cross-repo).
- **Ingress** (aws overlay only): `backend-api` with `ingressClassName: alb` and these annotations:
  - `scheme: internet-facing`, `target-type: ip`
  - `load-balancer-name: oncall-training-api` (fixed name, so the scripts can find it)
  - `healthcheck-path: /healthz`
  - `security-groups: <alb_security_group_id>`, `manage-backend-security-group-rules: "true"`
  - listener HTTP 80

### 5.2 Service accounts and RBAC (cross-repo with backend ARCHITECTURE §8.6)

All Roles live in namespace **`mock`** and are bound to service accounts in other namespaces with RoleBindings. There are no ClusterRoles.

| ServiceAccount | Role in `mock` | Rules |
|---|---|---|
| `app/backend-api` | `mock-reader` | `get,list,watch` on `pods`, `deployments` (apps); `get` on `pods/log` |
| `app/backend-worker` | `mock-operator` | `mock-reader` rules + `patch` on `deployments`, `deployments/scale` |
| `injector/injector` | `mock-injector` | `get,list` on `pods`; `delete` on `pods`; `get,patch` on `deployments`, `deployments/scale` |
| `mock/*` | none | `automountServiceAccountToken: false` |

AWS access for all pods comes from the node role (LabRole). There are no IAM annotations on service accounts.

### 5.3 NetworkPolicies (enforced by the VPC CNI)

| Namespace | Policy | Allows |
|---|---|---|
| all three | `default-deny-ingress` | nothing (ingress) |
| `app` | `allow-alb-to-api` | ingress to `backend-api:3000` from the VPC CIDR (ALB IP targets) |
| `mock` | `allow-from-app` | ingress to all mock pods on 8080 from namespace `app` (health checks) |
| `mock` | `allow-intra-mock` | ingress between mock pods on 8080 (gateway → orders → worker-svc) |
| `injector` | none | no ingress needed |

Egress isn't restricted in the MVP (pods need AWS APIs and Redis). Kubelet probes are allowed by the VPC CNI policy agent. Verify this during the smoke test (O-01).

### 5.4 Configuration

- `scripts/render-config.sh` reads the foundation and cluster outputs and writes `k8s/overlays/aws/config.env` (gitignored). Kustomize's `configMapGenerator` turns it into ConfigMap `oncall-config` in `app` and `injector`. The hash suffix triggers a rollout when it changes.
- Backend variables (names match backend ARCHITECTURE §9): `AWS_REGION`, `SESSIONS_TABLE`, `FILES_BUCKET`, `USER_ACTIONS_QUEUE_URL`, `STATE_MACHINE_ARN`, `ATHENA_WORKGROUP`, `ATHENA_DATABASE`, `REDIS_URL` (`rediss://…`), `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, `MOCK_NAMESPACE=mock`, `MOCK_HEALTH_URL_TEMPLATE=http://{service}.mock.svc.cluster.local:8080/health`, `AUTH_MODE=cognito`, `MOCK_CLUSTER=kubernetes`, `STATS_MODE=athena`.
- Injector variables: `AWS_REGION`, `FAULTS_QUEUE_URL`, `SESSIONS_TABLE`, `REDIS_URL`, `MOCK_NAMESPACE=mock`.
- No Kubernetes Secrets are needed in the MVP (no passwords; AWS credentials come from the node).

## 6. Step Functions — `oncall-training-scenario`

### 6.1 States (Standard workflow, `QueryLanguage: "JSONata"`)

```
Init (Pass: Assign input fields)
 → Warmup (Wait: Seconds = warmupSeconds)
 → InjectFault (sqs:sendMessage → faults)                    Catch ALL → MarkFailed(reason=ERROR)
 → WaitForFix (sqs:sendMessage.waitForTaskToken → user-actions.fifo, AWAIT_FIX)
       TimeoutSeconds = maxResolveSeconds
       Catch States.Timeout → MarkFailed(TIMEOUT) · Catch "Abandoned" → MarkFailed(ABANDONED) · Catch ALL → MarkFailed(ERROR)
 → PersistResolved (dynamodb:updateItem: state=RESOLVED, score fields, ended_at; condition state = INCIDENT_ACTIVE)
                                                            Catch ALL → MarkFailed(ERROR)
 → NotifyEnded (sqs:sendMessage → user-actions.fifo, SESSION_ENDED outcome=RESOLVED) → Succeed

MarkFailed (dynamodb:updateItem: state=FAILED, failure_reason, ended_at; condition state IN (STARTING, INCIDENT_ACTIVE))
 → NotifyEndedFailed (SESSION_ENDED outcome=FAILED, reason) → Fail
```

**Why SQS for the wait:** Step Functions' **DynamoDB integration doesn't support `.waitForTaskToken`**; only SQS, SNS, Lambda and a few others do. The state machine sends the token to the backend worker through `user-actions.fifo` (same FIFO group as the user's actions), and the worker stores it on the session item (DECISIONS D-13).

Example state (JSONata):
```json
"WaitForFix": {
  "Type": "Task",
  "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
  "Arguments": {
    "QueueUrl": "${user_actions_queue_url}",
    "MessageGroupId": "{% $sessionId %}",
    "MessageDeduplicationId": "{% $sessionId & ':await-fix' %}",
    "MessageBody": {
      "kind": "SYSTEM", "type": "AWAIT_FIX",
      "sessionId": "{% $sessionId %}", "userId": "{% $userId %}",
      "taskToken": "{% $states.context.Task.Token %}"
    }
  },
  "TimeoutSeconds": "{% $maxResolveSeconds %}",
  "Assign": { "result": "{% $states.result %}" },
  "Next": "PersistResolved",
  "Catch": [
    { "ErrorEquals": ["States.Timeout"], "Assign": { "reason": "TIMEOUT" }, "Next": "MarkFailed" },
    { "ErrorEquals": ["Abandoned"],      "Assign": { "reason": "ABANDONED" }, "Next": "MarkFailed" },
    { "ErrorEquals": ["States.ALL"],     "Assign": { "reason": "ERROR" }, "Next": "MarkFailed" }
  ]
}
```
`${…}` placeholders are filled by Terraform `templatefile()`; `{% … %}` is JSONata evaluated at run time.

### 6.2 Execution input (backend api → state machine) (cross-repo)
```json
{ "userId": "…", "sessionId": "…", "scenarioId": "orders-down",
  "warmupSeconds": 20, "maxResolveSeconds": 600,
  "fault": { "faultId": "…", "type": "SCALE_TO_ZERO", "target": { "namespace": "mock", "deployment": "orders" } } }
```
The execution name is `sessionId`.

### 6.3 Task output (backend worker `SendTaskSuccess`) (cross-repo)
```json
{ "resolvedAt": "…", "ttdSeconds": 42, "ttrSeconds": 131, "wrongActions": 1, "actionsCount": 4, "score": 802 }
```
To abandon, the backend calls `SendTaskFailure(error = "Abandoned")`.

## 7. Queue messages (cross-repo)

| Queue | Message | Producer → consumer | Group / dedup |
|---|---|---|---|
| `faults` (standard) | `FAULT` | state machine → injector | — (injector idempotent by `faultId`) |
| `user-actions.fifo` | `USER` action | backend api → backend worker | group `sessionId`, dedup `actionId` |
| `user-actions.fifo` | `SYSTEM` `AWAIT_FIX` | state machine → backend worker | group `sessionId`, dedup `<sessionId>:await-fix` |
| `user-actions.fifo` | `SYSTEM` `SESSION_ENDED` | state machine → backend worker | group `sessionId`, dedup `<sessionId>:ended` |

```json
// FAULT
{ "faultId": "…", "sessionId": "…", "userId": "…", "type": "SCALE_TO_ZERO" | "DELETE_PODS",
  "target": { "namespace": "mock", "deployment": "orders" }, "sentAt": "…" }
// AWAIT_FIX
{ "kind": "SYSTEM", "type": "AWAIT_FIX", "sessionId": "…", "userId": "…", "taskToken": "…" }
// SESSION_ENDED
{ "kind": "SYSTEM", "type": "SESSION_ENDED", "sessionId": "…", "userId": "…",
  "outcome": "RESOLVED" | "FAILED", "reason": "TIMEOUT" | "ABANDONED" | "ERROR" | null }
```
The USER action shape is owned by the backend (backend ARCHITECTURE §8.5).

## 8. Injector (`services/injector`)

- TypeScript / Node 22, `@aws-sdk/client-sqs`, `@aws-sdk/lib-dynamodb`, `ioredis`, `@kubernetes/client-node`, zod, pino.
- Loop: long-poll `faults` (`WaitTimeSeconds 20`). For each message:
  1. Parse it with zod; invalid messages are logged and left for the DLQ.
  2. Check the target: namespace must equal `MOCK_NAMESPACE`, and the deployment must be one of `gateway|orders|worker-svc`.
  3. **Apply** the fault (idempotent):
     - `SCALE_TO_ZERO`: patch `deployments/scale` to 0.
     - `DELETE_PODS`: delete the deployment's pods by label selector (the ReplicaSet recreates them, a short outage).
  4. **Record** (cross-repo, backend D-12): conditional `UpdateItem` on `Sessions` (`state = STARTING` → `INCIDENT_ACTIVE`, `fault_injected_at`, `updated_at`). `ConditionalCheckFailed` means it was already applied; that's fine. Then `RPUSH session:{id}:events` a `FAULT_INJECTED` event in the backend's event-line format, and refresh the key's TTL.
  5. Delete the message.
- Order matters: apply first, then record, so TTD/TTR never start before the fault exists.
- `SIGTERM`: stop polling, finish in-flight work, exit.
- `/healthz` on 8080.

## 9. Mock system (`services/mock-system`)

One image; `ROLE` selects the behavior. The chain is `gateway → orders → worker-svc`.

| Endpoint | Behavior |
|---|---|
| `GET /ping` | Always 200 if the process is up. Used for **liveness and readiness**, so a broken downstream doesn't make Kubernetes restart healthy pods. |
| `GET /health` | `gateway`: 200 if `orders /health` succeeds within 800 ms. `orders`: 200 if `worker-svc /ping` succeeds within 500 ms. `worker-svc`: 200 always. Otherwise 503 with `{ "status": "down", "reason": "…" }`. Body includes `latencyMs`. |
| `GET /metrics` | JSON: `{ requests, errors, p50LatencyMs, p95LatencyMs }` since start (planned for dashboard use) |

- **Synthetic traffic:** `gateway` calls `orders` every 500 ms and logs one line per request. It logs `info` on success and `error` on failure with the cause (`ECONNREFUSED orders.mock.svc.cluster.local:8080`, `timeout after 800ms`). That's what `VIEW_LOGS` shows the user.
- Baseline replicas (must match the scenario's `baseline` in the backend repo): gateway 1, orders 2, worker-svc 1.
- Logs are JSON lines for the dashboard, with a short `msg` field the logs viewer can show.

## 10. Data resources

### 10.1 DynamoDB `Sessions`
The table is created here; **its item shape is owned by the backend** (backend ARCHITECTURE §7.1). The state machine and the injector write the attributes listed there for them.

### 10.2 Glue table `session_events` (cross-repo with backend ARCHITECTURE §7.4)
- Location: `s3://oncall-training-files-<acct>/logs/`, SerDe `org.openx.data.jsonserde.JsonSerDe`.
- Columns: `ts string, user_id string, session_id string, scenario_id string, type string, action string, target string, params struct<replicas:int>, valid boolean, score int, ttd_seconds int, ttr_seconds int`.
- Partitions: `year string, month string, day string` with **partition projection**:
  - `projection.enabled = true`
  - `projection.year.type = integer`, range `2026,2030`
  - `projection.month.type = integer`, range `1,12`, digits `2`
  - `projection.day.type = integer`, range `1,31`, digits `2`
  - `storage.location.template = s3://…/logs/year=${year}/month=${month}/day=${day}/`
- No crawler and no `MSCK REPAIR`. The named queries themselves live in the backend repo.

## 11. CloudFront

| Behavior | Origin | Cache policy | Origin request policy | Extras |
|---|---|---|---|---|
| `/api/*` | ALB (`api_origin_domain`, HTTP only, port 80) | `Managed-CachingDisabled` | `Managed-AllViewerExceptHostHeader` (forwards `Authorization`, query strings, cookies) | allowed methods: all |
| default `*` | S3 site bucket via OAC | `Managed-CachingOptimized` | none | viewer-request Function **`spa-rewrite`** |

- `spa-rewrite` (cross-repo, frontend D-14): if the URI has no file extension, rewrite it to `/index.html`. **No custom error responses**: they apply to the whole distribution and would turn API 404s into `index.html` with status 200.
- Viewer protocol: redirect HTTP → HTTPS. Price class `PriceClass_100`. Default root object `index.html`. Uses the default `*.cloudfront.net` certificate (no custom domain).
- Origin updates take a few minutes to deploy after `update-api-origin.sh` runs.

## 12. Cognito

- App client URLs (cross-repo with the frontend):
  - callbacks: `https://<cloudfront_domain>/callback`, `http://localhost:5173/callback`
  - logout: `https://<cloudfront_domain>/`, `http://localhost:5173/`
- Managed login (v2) with default branding; self sign-up on; email verification via the Cognito default email sender (low daily limit, enough for a course).
- The e2e test user is created by `scripts/create-e2e-user.sh` (admin-create-user + set permanent password from an env var). It's **not** in Terraform, so the password never lands in state.

## 13. Operations

### 13.1 Lab session routine
1. Start the lab and check the remaining budget.
2. `make creds` (paste the "AWS CLI" block). This updates `~/.aws/credentials` and the GitHub secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` in the infra, backend and frontend repos.
3. `make cluster-up` if you need EKS today.
4. Work.
5. **`make cluster-down`.**

### 13.2 `make cluster-up`
1. `terraform -chdir=terraform/cluster apply` (VPC, EKS, node group, add-ons, LB controller, ElastiCache): about 15–20 min.
2. `aws eks update-kubeconfig --name oncall-training`.
3. `scripts/render-config.sh` → `k8s/overlays/aws/config.env`.
4. `kustomize build k8s/overlays/aws | kubectl apply -f -` with the current image tags (`k8s/overlays/aws/images.env`).
5. Wait for ALB `oncall-training-api` → `scripts/update-api-origin.sh` (applies foundation with `-var api_origin_domain=<alb dns>`).
6. `make status`.

### 13.3 `make cluster-down`
1. `kubectl delete ingress -n app backend-api` and **wait until the ALB is gone** (otherwise the controller-created ALB and its security group rules block the VPC destroy and keep billing).
2. `terraform -chdir=terraform/cluster destroy`.
3. Print a reminder that foundation stays up.

### 13.4 Deploying images
- **Backend:** its release workflow pushes `oncall-training/backend:<sha>`. To roll it out, run `make deploy BACKEND_TAG=<sha>` or the `deploy.yml` workflow with that input. It updates `images.env` (committed, so the running versions are visible in git), re-applies the overlay and waits for `kubectl rollout status`.
- **Injector / mock system:** `images.yml` builds and pushes on merge to `main` (when lab secrets are fresh); then deploy the same way.
- The frontend deploys itself to S3 and CloudFront (frontend ARCHITECTURE §11), using the `site_bucket` and `cloudfront_distribution_id` outputs.

### 13.5 Approximate cost (us-east-1, on-demand; check current pricing)

| Item | ≈ per hour | Stack |
|---|---|---|
| EKS control plane | $0.10 | cluster |
| 2× t3.medium | $0.083 | cluster |
| ALB (idle + minimal LCU) | $0.025 | cluster |
| ElastiCache cache.t3.micro | $0.017 | cluster |
| Public IPv4 addresses (2 nodes + 2 ALB) | $0.02 | cluster |
| **Cluster total** | **≈ $0.25/h (≈ $6/day if left up)** | |
| CloudFront, S3, DynamoDB on-demand, SQS, Step Functions, Cognito, ECR storage, Athena | cents per day at our usage | foundation |

## 14. Local (kind)

- `make kind-up`:
  1. creates a kind cluster `oncall-training` (optionally with Calico to enforce NetworkPolicies)
  2. builds the injector and mock-system images and runs `kind load docker-image`
  3. applies `k8s/overlays/local`
- The local overlay has no Ingress and uses local images (`imagePullPolicy: Never`). The injector points at the backend's LocalStack (`AWS_ENDPOINT_URL=http://host.docker.internal:4566`, Redis on the host). The backend runs outside kind (`pnpm dev`, `pnpm dev:worker`) with `MOCK_CLUSTER=kubernetes` and the kind kubeconfig.
- The local state machine: the backend keeps a copy at `local/statemachine.asl.json`. When `statemachines/scenario.asl.json` changes, tell the backend owner (or open a PR there).
