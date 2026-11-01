# Managed add-ons (ARCHITECTURE §4). Versions: the EKS default for the cluster version,
# which only changes when kubernetes_version does.

data "aws_eks_addon_version" "this" {
  for_each = toset(["vpc-cni", "kube-proxy", "coredns"])

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = false
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.this["vpc-cni"].version

  # EKS installs a self-managed copy first; take it over.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Enforces NetworkPolicies (INF-075..078).
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = data.aws_eks_addon_version.this["kube-proxy"].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# CoreDNS pods need nodes, or the add-on stays degraded and the apply times out.
resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = data.aws_eks_addon_version.this["coredns"].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}
