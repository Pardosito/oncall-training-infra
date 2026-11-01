# A queue plus its dead-letter queue (ARCHITECTURE §3), encrypted with SSE-SQS.

locals {
  suffix = var.fifo ? ".fifo" : ""
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq${local.suffix}"
  fifo_queue                = var.fifo ? true : null
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "this" {
  name                        = "${var.name}${local.suffix}"
  fifo_queue                  = var.fifo ? true : null
  content_based_deduplication = var.fifo ? false : null
  visibility_timeout_seconds  = var.visibility_timeout_seconds
  message_retention_seconds   = var.message_retention_seconds
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

# Only this queue may use the DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}
