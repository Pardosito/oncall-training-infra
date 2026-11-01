# ALB security group (INF-138, MVP) and the AWS Load Balancer Controller (INF-060).

# Attached to the ALB through the Ingress annotation `security-groups` (ARCHITECTURE §5.1).
# The controller adds the node-side rules itself (manage-backend-security-group-rules).
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB for the backend api: HTTP from the allowed CIDRs only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-alb" }
}

# MVP: the demo machines' public IPs. M2 swaps these for the CloudFront prefix list (INF-059).
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from an allowed demo IP (alb_ingress_cidrs)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id
  description       = "To pod IP targets inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 0
  to_port           = 65535
  cidr_ipv4         = aws_vpc.this.cidr_block
}

# Uses the node role (LabRole) through IMDS (hop limit 2); no IRSA in the lab.
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.2"

  wait    = true
  timeout = 600

  set = [
    { name = "clusterName", value = aws_eks_cluster.this.name },
    { name = "region", value = local.region },
    { name = "vpcId", value = aws_vpc.this.id },
    # Only Ingresses are used; don't intercept every Service of type LoadBalancer.
    { name = "enableServiceMutatorWebhook", value = "false" },
  ]

  depends_on = [
    aws_eks_access_policy_association.lab_admin,
    aws_eks_addon.coredns,
  ]
}
