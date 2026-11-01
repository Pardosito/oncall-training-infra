variable "owner" {
  type        = string
  description = "Who owns this lab account, for the Owner tag."
  default     = "ian"

  validation {
    condition     = contains(["ian", "jp"], var.owner)
    error_message = "owner must be \"ian\" or \"jp\"."
  }
}

variable "ecr_keep_images" {
  type        = number
  description = "How many images each ECR repository keeps; older ones are expired."
  default     = 15

  validation {
    condition     = var.ecr_keep_images >= 5 && var.ecr_keep_images <= 100
    error_message = "ecr_keep_images must be between 5 and 100."
  }
}
