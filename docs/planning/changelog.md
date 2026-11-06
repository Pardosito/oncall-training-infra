# On-Call Training: changelog

What changed in the project and in these notes, newest first. Details live in each area's decisions note: [Infra decisions](../DECISIONS.md) · [Back decisions](https://github.com/Pardosito/oncall-training-backend/blob/main/docs/DECISIONS.md) · [Front decisions](https://github.com/Pardosito/oncall-training-frontend/blob/main/docs/DECISIONS.md). Back to the [On-Call Training](README.md) hub.

---

## Tue Nov 3: backend MVP loop merged, frontend re-pinned

- Backend merged `feat/mvp-loop` (PR #132, `5ff88e6`).
- Frontend PR #127 re-pins `BACKEND_REF` to `5ff88e6`. The spec only adds the logs and abandon routes and `LogsResponse`, so no frontend code changed (they're for M2, #88/#89). CI passes; waiting for merge.

## Mon Nov 2: frontend history rewrite and re-pin

- Backend MVP loop built on `feat/mvp-loop` (not committed yet): backend D-29 to D-31, plus logs and abandon routes (see [Back decisions](https://github.com/Pardosito/oncall-training-backend/blob/main/docs/DECISIONS.md)). The frontend ran the full loop against it through the Vite proxy: resolved with score 902, every response matched the pinned spec.
- Frontend PR #126 (`feat/m1-mvp-foundation`) is merged to `main`.

- The backend merged `feat/m1-platform` into `main` (PR #131, regular merge). `BACKEND_REF` is re-pinned to `6710d2e`; the spec is byte-identical, so the types are unchanged. Frontend D-19 updated, L-11 resolved.
- Closed 67 frontend issues on GitHub, each with a comment naming its commit. Left open even though partly built: #26, #43, #44 (their Cognito criteria wait on #40) and #48 (nav on the landing page waits on #56). Still open for the MVP: #97.

## Sun Nov 1: frontend M1 + MVP implementation

- `oncall-front`, branch `feat/m1-mvp-foundation` (pushed, 13 commits + a re-pin commit on Nov 2, no PR yet): 71 of the 83 M1 + MVP issues implemented (11 deferred by D-20, FE-097 left) (see [Front plan (M1 + MVP)](front-plan.md) §8). The incident loop works end to end against MSW. 94 tests, lint, typecheck and build all pass.
- The frontend now uses the backend's real `openapi.json` (first pinned to `c94cd07` on `feat/m1-platform`; re-pinned on Nov 2, see below) instead of a draft. The backend added both frontend requests the same day: `actionsCount` on `SessionView` and an `ErrorCode` enum.
- New frontend decisions D-19 to D-24; D-20 (Cognito and similar issues to M2) is still **proposed**. D-14 marked Decided, O-01 and O-04 closed.
- Left for the MVP: FE-097, the run against EKS on Wed Nov 4.

## Fri Oct 30: M1 + MVP plan

**Notes**
- The folder is split into `Infra/`, `Back/` and `Front/`, with a hub ([On-Call Training](README.md)) and this changelog.
- `M1 implementation plan` → `Infra/Infra plan (M1 + MVP)`; `Infrastructure decisions` → `Infra/Infra decisions`. Content unchanged except the "Related" links.
- New: [Back plan (M1 + MVP)](back-plan.md), [Back decisions](https://github.com/Pardosito/oncall-training-backend/blob/main/docs/DECISIONS.md), [Front plan (M1 + MVP)](front-plan.md), [Front decisions](https://github.com/Pardosito/oncall-training-frontend/blob/main/docs/DECISIONS.md).

**Status found**
- GitHub: infra M1 0/50 and MVP 0/8; backend M1 0/22 and MVP 0/45; frontend M1 0/61 and MVP 0/22. The Oct 29 deliverable was missed in all three repos.
- Frontend repo: docs only. FE-001 is still open; AGENTS/CLAUDE/README are in `docs/` and should go back to the root.
- Docs drift: backend and frontend docs still say "Proposed" for items infra accepted on Oct 22 (infra D-14). Backend D-09 still describes an integration infra replaced (infra D-13).

**Proposed (waiting for review, nothing changed in the repos or on GitHub)**
- Infra: 8 review items (infra plan §10), e.g. EKS access entry only, compute the state bucket name, plain VPC resources, `linux/amd64` images.
- Backend: P-01 to P-11, e.g. contract-first spec on Sat, BE-034 into MVP, Redis client (BE-023) to M2, MVP config optional by mode, in-memory resolution counter, trimmed dev-inject.
- Frontend: P-01 to P-08, e.g. docs back to the root, draft-spec fallback, dev auth decoupled from Cognito, 20 issues deferred to M2.
- Cross-repo: X-1 to X-6 in the hub (workload split, milestone updates, handoff dates H1–H8).

## Tue Oct 27: M0 and the Nov 5 MVP

- Infra M0 done (15/15). The lab blocks `aws_s3_bucket` → `awscc_s3_bucket` (infra D-24).
- Backend M0 done (11/11): tooling, CI, templates, README; AGENTS/CLAUDE/README kept at the root.
- The course added a **rough MVP due Nov 5**: infra D-25, backend D-24 and frontend D-18. No Step Functions, Redis, Cognito or CloudFront until Nov 19. New MVP milestones and issues in all three repos (infra #138–140, backend #127–130, frontend #125).
- Project timelines updated in all three repos' AGENTS.md.

## Sun Oct 25

- Docs moved into `docs/` in the backend and frontend repos (the frontend move also took AGENTS/CLAUDE/README).

## Thu Oct 22: initial design

- Three repos, contracts and stack decided: infra D-01 to D-23, backend D-01 to D-23, frontend D-01 to D-17.
- Frontend switched from Tailwind + shadcn/ui to IBM Carbon (D-03), and from Recharts to Carbon Charts (D-04).
- Infra corrected the backend's Step Functions wait (infra D-13) and accepted its cross-repo proposals (infra D-14).
