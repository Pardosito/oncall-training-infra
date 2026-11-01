# EKS cluster, access and node group (ARCHITECTURE §4). Role = LabRole everywhere.

resource "aws_eks_cluster" "this" {
  name     = local.name
  version  = var.kubernetes_version
  role_arn = data.aws_iam_role.lab.arn

  access_config {
    authentication_mode = "API"
    # The creator is the voclabs role, which gets an explicit entry below. Letting EKS
    # also create one makes the explicit entry fail with "already exists" (D-26).
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = [for s in aws_subnet.public : s.id]
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Extended support costs 6× the standard hourly rate; never fall into it.
  upgrade_policy {
    support_type = "STANDARD"
  }

  # Control-plane logging stays off (cost).
  enabled_cluster_log_types = []

  depends_on = [aws_route_table_association.public]
}

# Cluster admin for the lab principal. The role ARN is stable across `make creds`,
# so kubectl keeps working after credentials rotate.
resource "aws_eks_access_entry" "lab_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_iam_session_context.current.issuer_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "lab_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.lab_admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_launch_template" "nodes" {
  name_prefix = "${local.name}-nodes-"
  description = "EKS nodes: IMDSv2 only, 20 GB gp3. AMI and instance type come from the node group."

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # pods (LB controller, injector) use the node role through IMDS
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name}-node" })
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = data.aws_iam_role.lab.arn
  subnet_ids      = [for s in aws_subnet.public : s.id]

  ami_type       = "AL2023_x86_64_STANDARD" # x86_64: images must be built for linux/amd64
  capacity_type  = "ON_DEMAND"              # the lab forbids Spot
  instance_types = [var.node_instance_type]

  scaling_config {
    min_size     = var.node_count
    desired_size = var.node_count
    max_size     = var.node_count + 1
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  # vpc-cni must be managed (network policy on) before pods get IPs.
  depends_on = [aws_eks_addon.vpc_cni, aws_eks_addon.kube_proxy]
}
