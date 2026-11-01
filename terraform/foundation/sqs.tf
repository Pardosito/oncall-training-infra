# Queues (ARCHITECTURE §7). Message shapes are a cross-repo contract.

# state machine (MVP: backend api) → injector
module "faults" {
  source = "../modules/queue-with-dlq"

  name                       = "${local.name}-faults"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  max_receive_count          = 3
}

# backend api + state machine → backend worker; group = sessionId, senders set the dedup id.
module "user_actions" {
  source = "../modules/queue-with-dlq"

  name                       = "${local.name}-user-actions"
  fifo                       = true
  visibility_timeout_seconds = 60
  max_receive_count          = 3
}
