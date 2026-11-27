# On-Call Training

**Practice handling a production incident before you're the one on call.**

On-Call Training is a web app where students and junior SDE/SREs work through a realistic outage. A small distributed system runs in Kubernetes on AWS. When you start a scenario, a real fault is injected into it: a deployment is scaled to zero, pods are deleted. You diagnose it from a live dashboard (service health, pods, logs, events) and fix it with predefined actions. The system detects the recovery on its own, scores you on time to detect, time to resolve and wrong moves, and keeps your history, charts and a per-scenario leaderboard.

This repo, **`oncall-training-infra`**, holds the infrastructure and orchestration: Terraform for every AWS resource, the Kubernetes manifests, the Step Functions state machine, and the two services that make the incident real (the **injector** and the **mock system**). The app lives in two sibling repos:

| Repo | Contains |
|---|---|
| **[oncall-training-infra](https://github.com/Pardosito/oncall-training-infra)** (this one) | Terraform, Kubernetes manifests, Step Functions, injector, mock system, `make` targets for the whole lifecycle |
| [oncall-training-backend](https://github.com/Pardosito/oncall-training-backend) | API + worker (Node/TypeScript), scenarios (JSON), `openapi.json` |
| [oncall-training-frontend](https://github.com/Pardosito/oncall-training-frontend) | React SPA (IBM Carbon) |

ITESO *Desarrollo en la Nube* course project, Fall 2026, team **Cafeinomanos**: Ian Rodríguez (infra and orchestration) and Juan Pablo González (backend and frontend).

## How it works

![Solution diagram](docs/solucion.jpg)

One incident, end to end:

1. **Start.** The user signs in with Cognito and starts a scenario. The request goes through **API Gateway**, which checks the token, then a VPC link and an internal ALB to the **API** pods in EKS. The API takes a lock in **ElastiCache** (one incident at a time), writes the session to **DynamoDB** and starts a **Step Functions** execution.
2. **Inject.** After a short warmup, the state machine sends a `FAULT` message to **SQS**. The **injector** consumes it and breaks the **mock system** (`gateway → orders → worker-svc`) through the Kubernetes API, for example by scaling `orders` to 0.
3. **Diagnose.** The backend **worker** rebuilds a dashboard snapshot every 2 s (replicas, pod status, latency, recent events) and caches it in ElastiCache. The SPA polls it. Upstream services degrade realistically: `gateway` reports `orders` as unreachable.
4. **Act.** The user acknowledges the incident, reads logs, and scales or restarts deployments. Actions go through a FIFO queue, so they apply in order for each session.
5. **Resolve.** When the system is healthy again, the worker completes the state machine's task token. Step Functions computes the score, stores it, and the worker restores the mock system to its baseline. If time runs out or the user abandons, the session ends as `FAILED` and the system is reset all the same.

### Scenarios

| Scenario | What the user sees | Notes |
|---|---|---|
| `orders-down` | Orders failing, storefront degraded | The introductory scenario |
| `checkout-failing` | Every service looks unhealthy | The real cause is `worker-svc`; fixing `orders` first counts as a wrong move |
| `storefront-down` | The entry point is down | A short warm-up |
| `peak-outage` | Checkout down during peak | Hard mode: no logs, 3 minutes, double time penalty, 100 points per wrong move |

Score = `base − TTD × perSecondTTD − TTR × perSecondTTR − wrongActions × perWrongAction`, with the weights set per scenario.

## Tech stack

**AWS services**

| Service | Used for |
|---|---|
| **EKS** (2× `t3.medium`, managed node group) | Runs the backend (`app`), the injector (`injector`) and the mock system (`mock`) in separate namespaces, isolated with RBAC and NetworkPolicies (VPC CNI) |
| **API Gateway** (HTTP API) | Fixed HTTPS URL for the API, Cognito JWT authorizer, CORS, throttling; VPC link to an internal ALB |
| **Step Functions** (Standard, JSONata) | Runs each scenario: `InjectFault → WaitForFix` (task token) `→ PersistResolved / MarkFailed → NotifyEnded` |
| **SQS** | `faults` (standard) and `user-actions.fifo`, each with a DLQ |
| **DynamoDB** | `Sessions` table plus a `Leaderboard` GSI; history, stats and rankings are queried from here |
| **ElastiCache** (Valkey, TLS) | Dashboard snapshots, the active-session lock, recent events |
| **Cognito** | User pool with managed login (Carbon-styled), self sign-up with email verification |
| **S3** | SPA hosting (website endpoint), scenario files and per-session event logs, Terraform state |
| **ECR** | Images tagged with git SHAs (immutable) |
| **ALB** + AWS Load Balancer Controller | Internal ALB owned by Terraform; pods registered through a `TargetGroupBinding` |

**Code and tooling**

- **Terraform** ≥ 1.10 (AWS provider 6.x, `awscc` for S3), split into a cheap, always-on `foundation` stack and an expensive, disposable `cluster` stack
- **Kubernetes** manifests with **Kustomize** (base plus `aws` and `local` overlays)
- **TypeScript / Node 22** for every service: injector, mock system, backend (Express, AWS SDK v3) and frontend (React, Vite, IBM Carbon, TanStack Query)
- **kind** + **LocalStack** for local runs, **Calico** to enforce NetworkPolicies locally
- **GitHub Actions** for CI (fmt/validate, tflint, kubeconform, checkov, lint, tests, image builds); one **Makefile** drives the whole lifecycle
- **mise** pins every CLI version (`mise.toml`)

## Running it

### Prerequisites

- An **AWS Academy Learner Lab** (us-east-1; no IAM resources can be created)
- **[mise](https://mise.jdx.dev)** for the pinned CLIs, **Docker** (image builds, kind), and **[GitHub CLI](https://cli.github.com)** logged in with access to the three repos

```bash
brew install mise                 # or: curl https://mise.run | sh
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc            # terminal
echo 'eval "$(mise activate zsh --shims)"' >> ~/.zprofile  # IDEs / GUI git clients; then restart the shell
mise install                      # terraform, kubectl, helm, node, pnpm, awscli, kind, …
pre-commit install                # fmt, validate, shellcheck, trailing whitespace
```

If a commit fails with "Neither Terraform nor OpenTofu binary could be found", mise isn't active in that shell.

### First time on a lab account

```bash
make creds              # paste the Learner Lab "AWS CLI" block: writes ~/.aws/credentials, updates the repos' AWS_* secrets
make bootstrap          # Terraform state bucket (local state, once per account)
make foundation-apply   # S3, DynamoDB, SQS, ECR, Cognito, API Gateway, Step Functions (cents per day)
make images             # build and push the injector and mock-system images; prints their tags
```

Then:
- **Backend:** run the backend's **Release** workflow, which pushes its image and uploads the scenarios.
- **Frontend:** fill its `.env.aws.local` from `make foundation-output` (Cognito IDs, `VITE_API_BASE_URL`), then run `SITE_BUCKET=<site bucket> pnpm deploy:s3`.

### Every work session

```bash
make creds                          # lab credentials expire with each session
make cluster-up                     # VPC, EKS, nodes, ElastiCache, internal ALB, manifests (~20 min)
make deploy BACKEND_TAG=<sha>       # roll out images; current tags are in k8s/overlays/aws/images.env
make status                         # nodes, pods, API URL, ALB target health, cost reminder
```

Open the site URL (`terraform -chdir=terraform/foundation output site_url`), create an account and start a scenario.

> [!WARNING]
> **Run `make cluster-down` before you stop working** (about 10 min). EKS, the nodes, the ALB and ElastiCache bill about **$0.25/h (≈ $6/day)** until they're destroyed, and the lab doesn't stop them for you. Run it even if `cluster-up` failed halfway. Foundation (data, users, images, the API's URL) stays up and survives cluster teardowns and lab restarts.

### Without AWS

| Goal | Command |
|---|---|
| Frontend only, simulated backend in the browser | `pnpm dev:mocks` (frontend repo) |
| Backend with an in-memory store and a simulated injector | `pnpm dev:memory` (backend repo) |
| Mock system + injector on a local cluster | `make kind-up` (`CALICO=1` enforces NetworkPolicies), then `make local-smoke` or `make netpol-test` |
| Every CI check | `make lint` |

### Common commands

| Command | Does |
|---|---|
| `make creds` | Load Learner Lab credentials locally and into the GitHub secrets |
| `make foundation-plan` / `make foundation-apply` | Plan / apply the always-on stack |
| `make cluster-up` / `make cluster-down` | Create / destroy the hourly-billed stack |
| `make deploy BACKEND_TAG=… [INJECTOR_TAG=…] [MOCK_TAG=…]` | Roll out images and wait for the rollout |
| `make status` | Cluster health at a glance |
| `make users USERS_FILE=f` / `make e2e-user` | Invite users / create the e2e test user |
| `make check-rbac` | Verify every service account can do exactly what it should |
| `make diagram` | Re-render `docs/solucion.png` from `docs/solucion.mmd` |

## Limitations

Most of these come from the AWS Academy Learner Lab, not from design choices. Each one is tracked in [DECISIONS.md](docs/DECISIONS.md#3-current-limitations) with its mitigation.

- **No IAM of our own.** Every pod and service runs as the lab's `LabRole`, so there's no per-workload least privilege (IRSA, Pod Identity). Namespaces, RBAC and NetworkPolicies are the isolation boundary.
- **No CloudFront, custom domain or certificate.** The SPA is served over **plain HTTP** from the S3 website endpoint. That also disables PKCE, and the sign-in code reaches the SPA unencrypted. The API itself is HTTPS at a fixed URL.
- **No Glue or Athena.** The lab role can't use them, so stats and leaderboards are computed with DynamoDB queries instead of SQL over S3.
- **One incident at a time.** All sessions share one mock system, so a global lock admits a single active incident. Others see a countdown until it's free.
- **One fault per scenario.** Only the scenario's first fault is injected; combined failures aren't supported yet.
- **Cost and startup time.** The cluster takes ~20 min to come up and must be torn down after each session. Credentials expire with every lab session.
- **No high availability or observability stack.** There's a single ElastiCache node, worker and injector, and no Prometheus or Grafana. Debugging uses `kubectl logs`, `make status` and the Step Functions console.
- **Not production networking.** Nodes run in public subnets without NAT, behind tight security groups, with no SSH and IMDSv2 required.

**Future work** with a real AWS account: IRSA and a GitHub OIDC deploy role; CloudFront with a custom domain and TLS; private subnets with VPC endpoints; one mock namespace per session so incidents can run concurrently; richer faults (latency, CPU, network partitions) with Chaos Mesh; Athena over the session event logs; Prometheus and Grafana; a nightly auto cluster-down. See [DECISIONS.md › Future improvements](docs/DECISIONS.md#4-future-improvements).

## Repository layout

```
terraform/
  bootstrap/        state bucket (local state, run once per account)
  foundation/       always on: S3, DynamoDB, Cognito, API Gateway, ECR, SQS, Step Functions
  cluster/          ephemeral: VPC, EKS, node group, add-ons, LB controller, internal ALB, ElastiCache
  modules/          small reusable modules (queue with DLQ)
statemachines/      scenario.asl.json (JSONata), rendered by Terraform
k8s/
  base/             namespaces, RBAC, NetworkPolicies, backend, injector, mock system
  overlays/aws/     ECR images, TargetGroupBinding, config rendered from Terraform outputs
  overlays/local/   kind: local images, LocalStack endpoints
services/
  injector/         consumes `faults`, breaks the mock system (TypeScript)
  mock-system/      one image, ROLE = gateway | orders | worker-svc (TypeScript)
scripts/            credentials, config rendering, deploy, status, kind, smoke tests
docs/               architecture, conventions, decisions, API, data model, diagram
```

## Documentation

| Read | For |
|---|---|
| [AGENTS.md](AGENTS.md) | Scope, Learner Lab constraints, stack, commands, rules for contributors |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Every AWS resource, the cluster layout, the state machine, the message contracts, operations, cost |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Every decision and why, known limitations, future improvements |
| [docs/CONVENTIONS.md](docs/CONVENTIONS.md) | How Terraform, manifests, services, scripts and workflows are written |
| [docs/api.md](docs/api.md) · [docs/modelo-datos.md](docs/modelo-datos.md) | API design and the DynamoDB data model (course deliverables, in Spanish) |
| [docs/BACKLOG.md](docs/BACKLOG.md) · [docs/planning/](docs/planning/README.md) | Issues by milestone, roadmap and changelog |

## Entrega del curso · Desarrollo en la Nube (ITESO, Otoño 2026)

**Proyecto:** On-Call Training · **Equipo:** Cafeinomanos

| Integrante | Rol |
|---|---|
| Ian Rodríguez | Infraestructura y orquestación (este repo) |
| Juan Pablo González | Backend y frontend |

| # | Entregable | Dónde |
|---|---|---|
| 1 | Diagrama de la solución | [docs/solucion.jpg](docs/solucion.jpg) (detallado: [docs/solucion.png](docs/solucion.png), fuente en [docs/solucion.mmd](docs/solucion.mmd)) |
| 2 | Modelo de datos | [docs/modelo-datos.md](docs/modelo-datos.md) |
| 3 | Diseño de la API | [docs/api.md](docs/api.md) |
| 4 | Código fuente | Backend + `Dockerfile`: [oncall-training-backend](https://github.com/Pardosito/oncall-training-backend). Infraestructura y servicios: [`terraform/`](terraform), [`k8s/`](k8s), [`services/`](services) (con sus `Dockerfile`), [`scripts/`](scripts) |
| 5 | Evidencia de despliegue | [docs/evidencias/](docs/evidencias/README.md) |
| 6 | Pendientes | [docs/pendientes.md](docs/pendientes.md) |

### Cambios respecto al diseño original

| Cambio | Por qué | Decisión |
|---|---|---|
| **Se agregó API Gateway** (HTTP API) delante de un ALB interno: URL HTTPS fija, CORS, validación del token de Cognito y throttling antes de llegar al cluster | La URL del ALB cambiaba con cada `cluster-up` y el ALB quedaba expuesto a internet | [D-33](docs/DECISIONS.md#d-33--api-gateway-http-api-in-front-of-an-internal-alb) |
| **Sin CloudFront**: la SPA se sirve desde el website endpoint de S3 (HTTP) | El Learner Lab no permite CloudFront | [D-31](docs/DECISIONS.md#d-31--s3-website-instead-of-cloudfront) |
| **Sin Glue ni Athena**: las estadísticas y el ranking salen directo de DynamoDB | El rol del Learner Lab no puede usar Glue ni Athena | [D-37](docs/DECISIONS.md#d-37--glue-and-athena-dropped) |

**Diferencias con la estructura sugerida.** El backend corre como contenedor, pero en **EKS** en lugar de una EC2 suelta. La API entra por **API Gateway**, que llega a los pods por un VPC link y un ALB interno ([api.md](docs/api.md)). Los recursos se crean con **Terraform** en lugar de scripts boto3, así que todo se puede volver a crear con un comando. Ninguna llave, contraseña, ARN ni id de cuenta está en el código: las credenciales del lab se cargan con `make creds` y los valores de cada cuenta salen de los outputs de Terraform.

## Operations

### Recovering the bootstrap state

The `bootstrap` stack keeps its state locally (`terraform/bootstrap/terraform.tfstate`, gitignored), because it creates the bucket every other stack stores its state in. If that file is lost (new laptop, fresh clone), the bucket is still there, so **don't** run `make bootstrap` again: it would try to create a bucket that already exists. Import it instead:

```bash
cd terraform/bootstrap
terraform init
BUCKET="oncall-training-tfstate-$(aws sts get-caller-identity --query Account --output text)"
terraform import awscc_s3_bucket.state "$BUCKET"
terraform plan   # should say "No changes"
cd ../.. && make backend-config   # rewrite foundation/ and cluster/ backend.hcl
```

### Switching to a new lab account

Everything is per account: the state bucket, the foundation resources and the images. After `make creds` with a different account:

```bash
make bootstrap           # archives the old local state to terraform/bootstrap/archive/<old account>/,
                         # creates this account's state bucket and rewrites both backend.hcl
make foundation-apply    # files bucket, Sessions, queues, Cognito, API Gateway, ECR (empty)
make images              # the injector and mock-system images don't carry over
```

Then run the backend's Release workflow so its image and scenarios exist in the new account, and redeploy the frontend with the new foundation outputs. If `backend.hcl` still points at another account's bucket, every foundation/cluster target stops with a message saying so.

### Demo: inject a fault by hand

```bash
make cluster-up && make deploy BACKEND_TAG=<sha>
make check-rbac                # every line "ok"
kubectl -n mock port-forward svc/gateway 8080:8080 &
curl -s localhost:8080/health  # {"status":"up",...}

# Send a FAULT by hand (ARCHITECTURE §7). The injector only applies faults for a session in
# STARTING, so create a throwaway session item first.
aws dynamodb put-item --table-name Sessions --item \
  '{"user_id":{"S":"demo"},"session_id":{"S":"demo"},"state":{"S":"STARTING"}}'
QUEUE=$(terraform -chdir=terraform/foundation output -raw faults_queue_url)
aws sqs send-message --queue-url "$QUEUE" --message-body \
  '{"faultId":"demo-1","sessionId":"demo","userId":"demo","type":"SCALE_TO_ZERO","target":{"namespace":"mock","deployment":"orders"}}'

kubectl -n mock get deploy orders          # 0/0
curl -s localhost:8080/health              # 503 {"status":"down","reason":"ECONNREFUSED ..."}
kubectl -n injector logs deploy/injector   # "scaled to zero"

kubectl -n mock scale deploy/orders --replicas=2   # the fix
curl -s localhost:8080/health              # up again
aws dynamodb delete-item --table-name Sessions --key '{"user_id":{"S":"demo"},"session_id":{"S":"demo"}}'

make cluster-down              # always
```
