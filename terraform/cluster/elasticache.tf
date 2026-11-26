# ElastiCache Valkey (ARCHITECTURE §4, D-09): the backend's lock, event buffer, health streak and
# dashboard snapshots, and the injector's FAULT_INJECTED events. Billed hourly, so it lives in the
# cluster stack and goes away with `make cluster-down` (AGENTS rule 5; cost in §12).

# INF-053: private subnets with a route table that has only the implicit local route. Nothing in
# them needs the internet: ElastiCache, the internal ALB and the API Gateway VPC link (D-33).
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${local.name}-private-${each.key}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-private" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# INF-061
resource "aws_elasticache_subnet_group" "this" {
  name        = local.name
  description = "Private subnets for the oncall-training Valkey node"
  subnet_ids  = [for s in aws_subnet.private : s.id]
}

# No egress rules: ElastiCache only answers connections.
resource "aws_security_group" "redis" {
  name        = "${local.name}-redis"
  description = "Valkey: 6379 from the EKS cluster security group only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-redis" }
}

# The managed node group's nodes carry the EKS cluster security group, and pods use the node's
# ENIs (no security groups for pods), so this covers the backend and the injector and nothing
# outside the cluster.
resource "aws_vpc_security_group_ingress_rule" "redis_from_cluster" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Valkey (TLS) from EKS nodes and pods (cluster security group)"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# INF-062: one node, no replicas or failover (L-05). TLS in transit and at rest cost nothing extra.
# No AUTH token: the security group is the access control, and a token would need secret handling.
# checkov (soft-fail) flags exactly these on purpose: CKV_AWS_31 (auth token, D-09), CKV_AWS_191
# (customer-managed KMS key: extra cost, AWS-owned key is enough), CKV2_AWS_50 (Multi-AZ, L-05).
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = local.name
  description          = "oncall-training: lock, event buffer, dashboard snapshots"

  engine             = "valkey"
  engine_version     = var.valkey_version
  node_type          = var.cache_node_type
  num_cache_clusters = 1
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true

  automatic_failover_enabled = false
  multi_az_enabled           = false
  snapshot_retention_limit   = 0 # the data is rebuilt within seconds or lost by design (L-03)
  auto_minor_version_upgrade = true
  apply_immediately          = true
}
