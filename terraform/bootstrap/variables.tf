variable "owner" {
  type        = string
  description = "Who owns this lab account, for the Owner tag."
  default     = "ian"

  validation {
    condition     = contains(["ian", "jp"], var.owner)
    error_message = "owner must be \"ian\" or \"jp\"."
  }
}
