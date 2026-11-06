# On-Call Training: changelog

What changed in the project, newest first. Details live in each area's decisions file: [Infra decisions](../DECISIONS.md) · [Back decisions](https://github.com/Pardosito/oncall-training-backend/blob/main/docs/DECISIONS.md) · [Front decisions](https://github.com/Pardosito/oncall-training-frontend/blob/main/docs/DECISIONS.md). Back to the [Roadmap](README.md).

---

## Thu Nov 5: intermediate delivery

- Infra: the deliverables for the course review are in `docs/`: solution diagram (`solucion.png`), data model, API design, deployment evidence and the to-do list for the final delivery.
- Infra D-28: no API Gateway. CloudFront is the edge and the ALB routes to the pods.
- Infra: `BACKEND_TAG` set to `2688b14`, so the backend runs on EKS with the rest of the system.

## Wed Nov 4: lab account switch

- Infra: the Makefile and scripts handle moving to a new lab account (`make bootstrap` archives the old local state and rewrites `backend.hcl`).
- Infra D-26 updated: the lab role ARN is parsed from the caller ARN, because the lab denies `iam:GetRole` on `voclabs`.

## Tue Nov 3: backend loop merged

- Backend merged the incident loop (PR #132). Its release workflow validates the scenarios and syncs them to S3.
- Frontend PR #127 re-pins `BACKEND_REF` to `5ff88e6`. The spec only adds the logs and abandon routes and `LogsResponse`, so no frontend code changed.

## Mon Nov 2: infra M1 merged, frontend on the real spec

- Infra merged `infra/m1-eks-up` (PR #142): foundation and cluster stacks, mock system, injector, manifests and the cluster lifecycle targets. The injector skips faults for sessions that already left `STARTING`.
- Backend merged its platform layer (PR #131). The frontend re-pinned `BACKEND_REF` to `6710d2e`; the spec was byte-identical.
- The frontend ran the full loop against the backend through the Vite proxy: resolved with score 902, every response matched the pinned spec.
- Frontend PR #126 merged: 71 of the 83 M1 + intermediate-delivery issues; Cognito and related issues moved to M2 (frontend D-20).

## Sun Nov 1: implementation

- Infra: foundation stack (S3, DynamoDB, SQS, ECR), cluster stack (VPC, EKS, node group, add-ons, LB controller), mock system and injector with tests, base manifests and the aws overlay, ops targets. New decisions D-26 and D-27.
- Backend: platform, contracts and the generated OpenAPI spec, Dockerfile, CI image build and ECR release workflow, domain logic (scoring, action rules, snapshot builder).
- Frontend: the incident loop works end to end against MSW. 94 tests, lint, typecheck and build pass. New frontend decisions D-19 to D-24.

## Fri Oct 30: plan for M1 and the intermediate delivery

- Per-area plans written for infra, backend and frontend, plus this roadmap.
- Order: infra builds the stacks and services while the backend publishes its spec first (contract-first), so the frontend works against the real contract.

## Tue Oct 27: M0 and the intermediate delivery

- Infra M0 done (15/15). The lab blocks `aws_s3_bucket` → `awscc_s3_bucket` (infra D-24).
- Backend M0 done (11/11): tooling, CI, templates, README.
- The course added an intermediate delivery on Nov 5 with one working flow: infra D-25, backend D-24 and frontend D-18. Step Functions, Redis, Cognito and CloudFront move to Nov 19.

## Sun Oct 25

- Docs moved into `docs/` in the backend and frontend repos.

## Thu Oct 22: initial design

- Three repos, contracts and stack decided: infra D-01 to D-23, backend D-01 to D-23, frontend D-01 to D-17.
- Frontend switched from Tailwind + shadcn/ui to IBM Carbon (D-03), and from Recharts to Carbon Charts (D-04).
- Infra corrected the backend's Step Functions wait (infra D-13) and accepted its cross-repo proposals (infra D-14).
