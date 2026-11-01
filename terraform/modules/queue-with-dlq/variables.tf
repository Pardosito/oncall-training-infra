variable "name" {
  type        = string
  description = "Queue name without the .fifo suffix; the DLQ gets \"-dlq\" appended."
}

variable "fifo" {
  type        = bool
  description = "Create FIFO queues (adds .fifo to both names). Content-based dedup stays off: senders set MessageDeduplicationId."
  default     = false
}

variable "visibility_timeout_seconds" {
  type        = number
  description = "Visibility timeout of the main queue."
  default     = 60

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200."
  }
}

variable "message_retention_seconds" {
  type        = number
  description = "Retention of the main queue. The DLQ keeps messages for 14 days so they can be inspected."
  default     = 345600

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600."
  }
}

variable "max_receive_count" {
  type        = number
  description = "Receives before a message moves to the DLQ."
  default     = 3

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be between 1 and 1000."
  }
}
