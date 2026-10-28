# On-Call Training — Infra · Agent Context

> Read this first. It explains what this repo is, what it is not, and the rules for working in it.
> Deeper docs:
> - `docs/ARCHITECTURE.md`: every AWS resource, the cluster layout, the state machine, the injector, the mock system, operations
> - `docs/CONVENTIONS.md`: how Terraform, Kubernetes manifests, services and workflows are written here
> - `docs/DECISIONS.md`: what we decided, why, current limitations and future improvements
>
> If you change a contract (queue message, state machine input/output, env var, RBAC, resource name), update `docs/ARCHITECTURE.md` in the same change, and tell the owner of the affected repo. Add every new decision to `docs/DECISIONS.md`.

## 1. The project in one paragraph

**On-Call Training** is a web app where students and junior SDE/SREs practice handling a production incident. A user starts a **scenario**. A real (mock) distributed system runs in EKS, and a fault is injected into it. The user diagnoses the problem from a live dashboard and fixes it with predefined actions. The system detects recovery, scores the attempt and stores it. Users then review their performance in charts built from Athena queries.

ITESO course project, team **Cafeinomanos**: **Ian Rodríguez** (infra and orchestration, **owner of this repo**) and Juan Pablo González (application and data). It is also meant to be a CV-quality project.

## 2. What this repo is (and isn't)

| Repo | Contains |
|---|---|
| **`oncall-training-infra`** (this one) | **Terraform** for every AWS resource. **Kubernetes manifests** for all workloads (including the backend's). The **Step Functions** definition. The **injector** and the **mock system** (TypeScript services). Workflows to build their images, bring the cluster up and down, and roll out images. |
| `oncall-training-backend` | API + worker code, its Dockerfile, scenarios, `openapi.json`. Pushes its image to ECR. |
| `oncall-training-frontend` | React SPA. Deploys its build to the S3 site bucket created here. |

**Not in this repo:** backend or frontend code, scenario definitions, Athena named queries (they live in the backend's `stats` module). This repo provides the resources they use.

## 3. MVP scope

In scope:
- the AWS resources in ARCHITECTURE §3–4
- one EKS cluster with namespaces `app`, `injector`, `mock`, separated by RBAC and NetworkPolicies
- the scenario state machine
- an injector that applies `SCALE_TO_ZERO` and `DELETE_PODS`
- a 3-service mock system (`gateway → orders → worker-svc`)
- a cheap, repeatable cluster lifecycle (`make cluster-up` / `make cluster-down`)
- a local kind setup for the mock system and injector

Out of scope unless the team asks: multiple environments (dev/stage/prod), custom domains and certificates, GitOps (Argo CD/Flux), Prometheus/Grafana, service mesh, autoscaling (Karpenter/HPA), multi-region, extra fault types.

## 4. AWS Learner Lab constraints (read before writing Terraform)

- **No IAM creation.** Never declare `aws_iam_role`, `aws_iam_policy`, `aws_iam_role_policy_attachment`, `aws_iam_openid_connect_provider`, IRSA or Pod Identity associations. Look up the existing role with `data "aws_iam_role" "lab" { name = "LabRole" }` and use its ARN everywhere a role is required. Service-linked roles are fine.
- **Region:** `us-east-1` only.
- **EC2:** nano to large instance types, **On-Demand only** (no Spot), at most 9 instances and 32 vCPU per region.
- **Credentials expire with each lab session.** Refresh them with `make creds`. Never hardcode keys, account IDs or ARNs.
- **Billing continues after the lab session ends** for EKS, the ALB, ElastiCache and public IPv4 addresses. **Run `make cluster-down` at the end of every work session.** If the lab budget runs out, the account can be disabled and its resources deleted.
- The shared environment lives in **Ian's lab account**. All code must work in any lab account through variables and data sources.

## 5. Stack

| Concern | Choice |
|---|---|
| IaC | **Terraform** ≥ 1.10, AWS provider ~> 6.x, Helm provider for the LB controller. **Two stacks** (`foundation`, `cluster`) + `bootstrap`. State in S3 with native lock file (`use_lockfile = true`) |
| Kubernetes | **Amazon EKS** (managed node group, 2× `t3.medium`, AL2023), **Kustomize** (base + `local` and `aws` overlays) |
| Networking | VPC with 2 AZs; **public subnets for nodes and the ALB, no NAT**; private subnets for ElastiCache |
| Ingress | **AWS Load Balancer Controller** → ALB (IP targets), restricted to CloudFront |
| Network policy | Amazon VPC CNI with network policy enforcement enabled |
| Orchestration | **AWS Step Functions**, Standard workflow, **JSONata** |
| Queues | SQS `faults` (standard) + DLQ; `user-actions.fifo` + DLQ |
| Data | DynamoDB `Sessions`, S3 (`files`, `site`), Glue table with partition projection, Athena workgroup |
| Cache | **ElastiCache** Valkey, single small node, TLS on |
| Auth | Cognito User Pool, managed login, public app client (PKCE) |
| CDN | CloudFront: S3 origin with OAC + ALB origin for `/api/*`; CloudFront Function for SPA routing |
| Images | Amazon ECR, tags = git SHA, immutable |
| Services here | **TypeScript / Node 22** (injector, mock system), pnpm workspace, Vitest |
| Local | **kind** (+ optional Calico for NetworkPolicies), LocalStack from the backend's docker-compose |
| CI / ops | GitHub Actions + **Makefile** (workflows call the same make targets) |
| Checks | `terraform fmt/validate`, `tflint`, `kustomize build` + `kubeconform`, `checkov` (soft-fail) |

## 6. Commands

```bash
make creds                 # paste Learner Lab "AWS CLI" block → ~/.aws/credentials + GitHub secrets in the 3 repos
make bootstrap             # once per lab account: state bucket (local state)
make foundation-plan       # terraform plan for foundation
make foundation-apply      # ⚠ creates/changes AWS resources (asks for confirmation)
make cluster-up            # ⚠ cluster stack + kubeconfig + config render + k8s apply + CloudFront API origin update (~20 min)
make deploy BACKEND_TAG=<sha> [INJECTOR_TAG=<sha>] [MOCK_TAG=<sha>]   # roll out images, wait for rollout
make status                # nodes, pods per namespace, ALB DNS, cost reminder
make cluster-down          # ⚠ delete Ingress (removes ALB) → wait → terraform destroy cluster
make images                # build + push injector and mock-system images (git SHA tag)
make kind-up / kind-down   # local cluster with mock system + injector
make lint                  # fmt, validate, tflint, kubeconform, pnpm lint/test
```

## 7. Repository layout

```
oncall-training-infra/
├── AGENTS.md · CLAUDE.md · README.md · Makefile
├── docs/                    ARCHITECTURE.md · CONVENTIONS.md · DECISIONS.md
├── terraform/
│   ├── bootstrap/           state bucket (local state, run once)
│   ├── foundation/          cheap, always on: S3, DynamoDB, Cognito, ECR, SQS, Step Functions, Glue/Athena, CloudFront
│   ├── cluster/             expensive, ephemeral: VPC, EKS, node group, add-ons, LB controller, ElastiCache
│   └── modules/             small local modules only when reused (e.g. queue-with-dlq)
├── statemachines/
│   └── scenario.asl.json    JSONata definition, rendered by Terraform templatefile()
├── k8s/
│   ├── base/                namespaces · rbac · networkpolicies · app/ (backend api, worker) · injector/ · mock/
│   └── overlays/
│       ├── aws/             ECR images, Ingress, config from Terraform outputs
│       └── local/           kind: local images, no Ingress, LocalStack endpoints
├── services/
│   ├── injector/            TypeScript: consumes `faults`, breaks the mock system
│   └── mock-system/         TypeScript: one image, ROLE = gateway | orders | worker-svc
├── scripts/                 lab-creds.sh · render-config.sh · update-api-origin.sh · kind-up.sh
└── .github/workflows/       ci.yml · images.yml · cluster.yml · deploy.yml
```

## 8. Rules for agents

1. **Stay in scope** (§3). If a request needs a new AWS service or a new kind of resource, stop and ask.
2. **Never run `terraform apply`, `terraform destroy`, `make foundation-apply`, `make cluster-up`, `make cluster-down`, `make deploy`, `kubectl apply/delete` against EKS, or `aws` commands that change resources, without explicit confirmation.** `plan`, `validate`, `kustomize build`, kind and LocalStack are fine.
3. **All AWS resources go through Terraform.** If something was clicked in the console, backport it or delete it.
4. **Learner Lab rules (§4) are hard constraints.** No IAM resources, us-east-1, On-Demand, small instances.
5. **Cost awareness:** anything billed hourly goes in the `cluster` stack, never `foundation`. Any new hourly resource needs a decision entry with its cost.
6. **No secrets in the repo.** No keys, passwords or session tokens in `.tf`, `.tfvars`, YAML or workflows. `*.tfvars` with real values and `k8s/overlays/aws/config.env` are gitignored.
7. **Contracts are shared.** Queue messages, the state machine input/output, RBAC rules and env vars used by the backend are listed in ARCHITECTURE §6–9. Change them only together with the backend owner.
8. **Kubernetes:** namespaced Roles only (no ClusterRoles for workloads), default-deny NetworkPolicies, probes and resource limits on every container, images by git SHA tag.
9. **Tests** are part of the change for the injector and mock system (fault parsing, idempotency, health logic).
10. Follow `docs/CONVENTIONS.md`. Prefer small PRs, one concern each, with the `terraform plan` summary pasted for infra changes.
11. **No AI attribution.** Never add yourself as a co-author: no `Co-Authored-By` trailers in commits and no "Generated with …" lines in PR descriptions or issues.

## 9. Timeline (course)

| Date | Deliverable relevant to this repo |
|---|---|
| Thu Oct 29 | EKS up; backend, mock system and injector running in separate namespaces; injector kills and the system can be revived |
| Thu Nov 19 | Step Functions + both SQS queues integrated; ElastiCache serving the dashboard |
| Thu Nov 26 | Glue/Athena ready for the charts; e2e happy path on the deployed stack |

## 10. Glossary

- **foundation / cluster**: the two Terraform stacks. Foundation is cheap and stays up; the cluster stack is expensive and destroyed when idle.
- **Fault**: a destructive change to the mock system, sent by the state machine to `faults` and applied by the injector.
- **Baseline**: the healthy replica counts of the mock system (from the scenario).
- **AWAIT_FIX**: system message the state machine sends to `user-actions.fifo` carrying its task token; the backend worker stores it and later calls `SendTaskSuccess`.
- **SESSION_ENDED**: system message sent on every terminal path so the backend cleans up.
