# oncall-training-infra

Infrastructure for **On-Call Training**, a web app where students and junior SDE/SREs practice handling a production incident: a mock distributed system runs in EKS, a fault is injected, and the user diagnoses and fixes it from a live dashboard.

This repo holds:
- **Terraform** for every AWS resource, in three stacks: `bootstrap` (state bucket), `foundation` (cheap, always on) and `cluster` (EKS and everything billed hourly)
- **Kubernetes manifests** (Kustomize) for all workloads, including the backend's
- the **Step Functions** state machine that drives a scenario
- the **injector** and the **mock system**, two small TypeScript services
- the workflows and `make` targets that build images, bring the cluster up and down, and roll out releases

The app itself lives in [`oncall-training-backend`](https://github.com/Pardosito/oncall-training-backend) and [`oncall-training-frontend`](https://github.com/Pardosito/oncall-training-frontend).

> **Status:** M0 (setup) done. M1 code written: foundation and cluster Terraform, injector, mock system, manifests and the cluster lifecycle targets. Not applied yet: foundation, the first cluster apply (spike) and the first image push are next. Then the first MVP, one incident loop on EKS (Thu Nov 5, [DECISIONS D-25](docs/DECISIONS.md)). Run `make help` for the targets that exist today.

## Docs

| Read | For |
|---|---|
| [AGENTS.md](AGENTS.md) | Start here: scope, Learner Lab constraints, stack, commands, repo layout, rules |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Every AWS resource, the cluster layout, contracts, operations |
| [docs/CONVENTIONS.md](docs/CONVENTIONS.md) | How Terraform, manifests, services, scripts and workflows are written |
| [docs/DECISIONS.md](docs/DECISIONS.md) | What we decided and why, known limitations, future work |
| [docs/BACKLOG.md](docs/BACKLOG.md) | Every issue, by milestone |

## Prerequisites

- An **AWS Academy Learner Lab** session (us-east-1 only; no IAM resources can be created)
- **[mise](https://mise.jdx.dev)**, which installs every other CLI at the pinned version (see [Tooling](#tooling))
- **Docker**, for building images and running kind
- **[GitHub CLI](https://cli.github.com)** (`gh`), logged in with access to the infra, backend and frontend repos, so `make creds` can update their secrets

## Tooling

All CLI versions are pinned in [`mise.toml`](mise.toml): terraform, tflint, kubectl, kustomize, kubeconform, kind, helm, node 22, pnpm, shellcheck, awscli v2 and pre-commit.

```bash
brew install mise                 # or: curl https://mise.run | sh
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc            # terminal
echo 'eval "$(mise activate zsh --shims)"' >> ~/.zprofile  # IDEs / GUI git clients; then restart the shell
mise install                      # installs every pinned tool for this repo
mise ls --current                 # check what's active
pre-commit install                # git hooks: fmt, validate, shellcheck, trailing whitespace
```

Inside the repo, mise puts the pinned versions first on your `PATH`. The pre-commit hooks need this too: if a commit fails with "Neither Terraform nor OpenTofu binary could be found", mise isn't activated in that shell.

## Lab session routine

Lab credentials expire at the end of every session, and the cluster stack costs about **$0.25/h (≈ $6/day)** while it's up. So every session goes like this:

1. **Start the lab** and check the remaining budget.
2. **`make creds`** and paste the "AWS CLI" block. This writes `~/.aws/credentials` and updates the `AWS_*` GitHub secrets in all three repos.
3. **`make cluster-up`** only if you need EKS today (about 20 min). For most work, use kind instead: `make kind-up`.
4. Work.
5. **`make cluster-down`.**

> [!WARNING]
> **Always run `make cluster-down` before you stop working.** The lab doesn't stop the cluster for you: EKS, the nodes, the ALB and ElastiCache keep billing until they're destroyed, and a forgotten cluster can drain the lab budget. Run it even if `cluster-up` failed halfway. `foundation` (data, users, images) stays up and costs cents per day.

First time in a new lab account, run `make bootstrap` once (after `make creds`) to create the Terraform state bucket.

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

## First time on a lab account (after `make bootstrap`)

```bash
make foundation-apply          # S3, DynamoDB, SQS, ECR (cheap, stays up)
make foundation-output         # share the queue URLs, table and ECR URLs with the team
cp terraform/cluster/terraform.tfvars.example terraform/cluster/cluster.auto.tfvars
# edit alb_ingress_cidrs: your and your teammate's public IP (curl -s https://checkip.amazonaws.com)
make images                    # needs Docker; builds linux/amd64 and pushes with the git SHA tag
```

## Demo: kill and revive (INF-123)

```bash
make cluster-up                # ~20 min; then:
make deploy MOCK_TAG=<sha> INJECTOR_TAG=<sha>   # the tags printed by make images
make check-rbac                # every line "ok"
kubectl -n mock port-forward svc/gateway 8080:8080 &
curl -s localhost:8080/health  # {"status":"up",...}

# Send a FAULT by hand (ARCHITECTURE §7). The session item doesn't exist, so the record step
# logs "already-recorded"; the fault is still applied.
QUEUE=$(terraform -chdir=terraform/foundation output -raw faults_queue_url)
aws sqs send-message --queue-url "$QUEUE" --message-body \
  '{"faultId":"demo-1","sessionId":"demo","userId":"demo","type":"SCALE_TO_ZERO","target":{"namespace":"mock","deployment":"orders"}}'

kubectl -n mock get deploy orders          # 0/0
curl -s localhost:8080/health              # 503 {"status":"down","reason":"ECONNREFUSED ..."}
kubectl -n injector logs deploy/injector   # "scaled to zero"
kubectl -n mock logs deploy/gateway        # "GET /orders failed: ..."

kubectl -n mock scale deploy/orders --replicas=2   # the fix
curl -s localhost:8080/health              # up again

make cluster-down              # always
```
