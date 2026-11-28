# Only the cluster (control plane, managed nodes and Karpenter nodes share this security
# group) may reach the database and the cache. No CIDR ranges, no internet path.
# Inside the cluster, NetworkPolicy narrows it further to the backend pods.
resource "aws_security_group" "db" {
  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL: 5432 from the EKS cluster only"
  vpc_id      = local.network.vpc_id
  tags        = { Name = "${local.name}-aurora" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_cluster" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from EKS nodes and pods"
  referenced_security_group_id = local.eks.cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_security_group" "cache" {
  name        = "${local.name}-valkey"
  description = "Valkey serverless: 6379 from the EKS cluster only"
  vpc_id      = local.network.vpc_id
  tags        = { Name = "${local.name}-valkey" }
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_cluster" {
  security_group_id            = aws_security_group.cache.id
  description                  = "Valkey (TLS) from EKS nodes and pods"
  referenced_security_group_id = local.eks.cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
}
