# Internal ALB for the backend api (D-33) and the AWS Load Balancer Controller (INF-060).
# Terraform owns the ALB, its listener and target group; the controller only registers the
# backend-api pod IPs through the TargetGroupBinding in k8s/overlays/aws. So `make cluster-down`
# is a plain terraform destroy: nothing in AWS is owned by Kubernetes.
# Only API Gateway reaches it, through the VPC link (api.tf); it has no public IPs.

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Internal ALB for the backend api: HTTP from the API Gateway VPC link only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_vpc_link" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP from the API Gateway VPC link"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.vpc_link.id
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id
  description       = "To pod IP targets inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 0
  to_port           = 65535
  cidr_ipv4         = aws_vpc.this.cidr_block
}

# Pods use the node ENIs, which carry the EKS cluster security group.
resource "aws_vpc_security_group_ingress_rule" "pods_from_alb" {
  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description                  = "backend-api pods from the internal ALB"
  ip_protocol                  = "tcp"
  from_port                    = local.api_port
  to_port                      = local.api_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_lb" "api" {
  name               = "${local.name}-api"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.private : s.id]

  drop_invalid_header_fields = true
  idle_timeout               = 60
}

resource "aws_lb_target_group" "api" {
  name                 = "${local.name}-api"
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = local.api_port
  vpc_id               = aws_vpc.this.id
  deregistration_delay = 15

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP" # private hop; TLS ends at API Gateway

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
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
