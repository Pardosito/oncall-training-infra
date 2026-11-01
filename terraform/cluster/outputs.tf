# Contract outputs (ARCHITECTURE §4): used by render-config.sh and the make targets.

output "cluster_name" {
  description = "EKS cluster name (aws eks update-kubeconfig --name …)."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "vpc_id" {
  description = "VPC of the cluster."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR; the ALB reaches pod IPs from it (NetworkPolicy allow-alb-to-api)."
  value       = aws_vpc.this.cidr_block
}

output "alb_security_group_id" {
  description = "Security group for the backend-api ALB (Ingress annotation)."
  value       = aws_security_group.alb.id
}
