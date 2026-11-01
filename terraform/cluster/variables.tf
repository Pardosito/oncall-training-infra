variable "owner" {
  type        = string
  description = "Who owns this lab account, for the Owner tag."
  default     = "ian"

  validation {
    condition     = contains(["ian", "jp"], var.owner)
    error_message = "owner must be \"ian\" or \"jp\"."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version. Use the current default: aws eks describe-cluster-versions --default-only. Stay within ±1 minor of kubectl in mise.toml."
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.(3[3-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.33 … 1.39."
  }
}

variable "node_instance_type" {
  type        = string
  description = "EC2 instance type of the node group. The lab allows nano to large, On-Demand only."
  default     = "t3.medium"

  validation {
    condition     = can(regex("^t(3|3a|4g)\\.(nano|micro|small|medium|large)$", var.node_instance_type))
    error_message = "node_instance_type must be t3/t3a/t4g, nano to large (Learner Lab limit)."
  }
}

variable "node_count" {
  type        = number
  description = "Desired (and minimum) number of nodes. Max is one more."
  default     = 2

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 4
    error_message = "node_count must be between 1 and 4 (the lab allows 9 instances per region)."
  }
}

variable "alb_ingress_cidrs" {
  type        = list(string)
  description = "MVP only (INF-138): public IPs allowed to reach the ALB on port 80, e.g. [\"203.0.113.7/32\"]. Set real values in cluster.auto.tfvars (gitignored). Replaced by the CloudFront prefix list in M2 (INF-059)."
  default     = []

  validation {
    condition     = alltrue([for c in var.alb_ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "Every alb_ingress_cidrs entry must be a valid CIDR."
  }

  validation {
    condition     = !contains(var.alb_ingress_cidrs, "0.0.0.0/0")
    error_message = "The ALB must not be open to 0.0.0.0/0 (CONVENTIONS §1.6)."
  }
}
