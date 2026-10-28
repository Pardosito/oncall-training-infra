<!-- Title: Conventional Commit, e.g. `feat(cluster): add ElastiCache Valkey replication group` -->

Closes #

## What
<!-- The change, in a few bullets. -->

## Why
<!-- The problem it solves, or the issue / decision (D-xx) it implements. -->

## `terraform plan` summary
<!-- One line per stack this PR touches (the "Plan: X to add, …" line). Delete the ones it doesn't. Write "n/a" if no Terraform changed. -->

| Stack | Add | Change | Destroy | Notes |
|---|---|---|---|---|
| bootstrap |  |  |  |  |
| foundation |  |  |  |  |
| cluster |  |  |  |  |

## Cost impact
<!-- New or changed billed resources and their hourly/daily cost. Hourly-billed resources belong in `cluster` (AGENTS §8.5). Write "none" if nothing changes. -->

## Contract change
<!-- Queue messages, state machine I/O, RBAC, ConfigMap keys, Terraform outputs (ARCHITECTURE §6–9). -->

- [ ] No contract change
- [ ] Contract change: backend action needed: <!-- what -->
- [ ] Contract change: frontend action needed: <!-- what -->

## Checks
- [ ] `make lint` passes (fmt, validate, tflint, kubeconform, pnpm lint/test)
- [ ] No secrets, no IAM resources, `us-east-1` only
