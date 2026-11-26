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

output "api_target_group_arn" {
  description = "Target group of the internal ALB; the TargetGroupBinding registers the backend-api pods in it (D-33)."
  value       = aws_lb_target_group.api.arn
}

output "redis_endpoint" {
  description = "REDIS_URL for the backend and the injector: TLS (rediss://), no AUTH token (D-09)."
  value       = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}
