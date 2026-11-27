# ---------------------------------------------------------------------------
# Aurora PostgreSQL Serverless v2 ("Aurora" in the diagram).
#   role = primary   : the writer in Mumbai. With dr_region set it becomes an Aurora Global
#                      Database (storage-level replication to the DR region, typically < 1 s lag).
#   role = secondary : the read-only copy in Frankfurt (dr workspace). Headless by default:
#                      replicated storage, no instance, until a failover drill adds one.
# pgvector (Phase 9) will run on this same database.
# ---------------------------------------------------------------------------
data "aws_rds_engine_version" "postgres" {
  engine  = "aurora-postgresql"
  version = var.aurora_postgres_major
  latest  = true
}

locals {
  # Global databases cannot auto-pause (AWS docs), so the floor is 0.5 ACU while DR is on.
  min_acu       = local.global || !local.is_primary ? 0.5 : 0
  pause_seconds = local.global || !local.is_primary ? null : var.aurora_auto_pause_seconds
  cluster       = one(concat(aws_rds_cluster.primary, aws_rds_cluster.secondary))
}

resource "aws_db_subnet_group" "this" {
  name        = "${local.name}-aurora"
  description = "Private subnets only"
  subnet_ids  = local.network.private_subnet_ids
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${local.name}-aurora-pg"
  family      = data.aws_rds_engine_version.postgres.parameter_group_family
  description = "TLS required, connections logged"

  parameter {
    name  = "rds.force_ssl"
    value = "1" # plaintext connections are refused
  }

  parameter {
    name  = "log_connections"
    value = "1" # who connected, from where (audit trail in CloudWatch)
  }

  # Audit schema changes and catch slow queries, but do not log every statement:
  # full query logs would copy user data into CloudWatch.
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # ms
  }
}

# ---------------------------------------------------------------------------
# Admin password. RDS-managed passwords are not supported with Aurora Global Database
# (AWS docs), so Terraform generates one as an *ephemeral* value and writes it with
# write-only arguments: it reaches RDS and Secrets Manager but never Terraform state or Git.
# The secret is replicated to the DR region for the db-migrate job there.
# ---------------------------------------------------------------------------
ephemeral "random_password" "admin" {
  count            = local.is_primary ? 1 : 0
  length           = 32
  override_special = "!#%&*()-_=+[]{}<>:?" # Aurora rejects / " @ and spaces
}

resource "aws_secretsmanager_secret" "admin" {
  #checkov:skip=CKV2_AWS_57:No rotation Lambda in dev; rotate by bumping admin_password_version (Phase 8 adds scheduled rotation)
  count                   = local.is_primary ? 1 : 0
  name                    = "${local.name}/aurora-admin"
  description             = "Aurora admin login, read only by the db-migrate job"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = 0 # dev: allow immediate re-create after destroy

  dynamic "replica" {
    for_each = aws_kms_replica_key.data_dr
    content {
      region     = var.dr_region
      kms_key_id = replica.value.arn
    }
  }
}

resource "aws_secretsmanager_secret_version" "admin" {
  count     = local.is_primary ? 1 : 0
  secret_id = aws_secretsmanager_secret.admin[0].id
  secret_string_wo = jsonencode({
    username = "dbadmin"
    password = ephemeral.random_password.admin[0].result
  })
  secret_string_wo_version = var.admin_password_version
}

resource "aws_rds_cluster" "primary" {
  #checkov:skip=CKV_AWS_139:Deletion protection is a variable; off in dev so the test run can be destroyed
  #checkov:skip=CKV2_AWS_27:Logs DDL and slow queries (parameter group); logging every statement would copy user data into logs
  #checkov:skip=CKV2_AWS_8:AWS Backup plans are out of scope for dev; Aurora automated backups and the global database cover recovery
  count              = local.is_primary ? 1 : 0
  cluster_identifier = local.name
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" # Serverless v2 runs on the provisioned engine mode
  engine_version     = data.aws_rds_engine_version.postgres.version_actual
  database_name      = var.database_name

  master_username            = "dbadmin"
  master_password_wo         = ephemeral.random_password.admin[0].result
  master_password_wo_version = var.admin_password_version

  # The app logs in with a 15-minute IAM token (Pod Identity), never a password.
  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.data.arn

  backup_retention_period         = 1 # dev; 7 to 35 in prod
  preferred_backup_window         = "20:00-21:00"
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = !var.deletion_protection
  final_snapshot_identifier       = var.deletion_protection ? "${local.name}-final" : null
  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity             = local.min_acu
    max_capacity             = var.aurora_max_acu
    seconds_until_auto_pause = local.pause_seconds
  }

  # The global cluster adopts this cluster (source_db_cluster_identifier) and sets this field.
  lifecycle {
    ignore_changes = [global_cluster_identifier]
  }
}

resource "aws_rds_cluster_instance" "writer" {
  #checkov:skip=CKV_AWS_353:Performance Insights costs extra; enable in prod
  #checkov:skip=CKV_AWS_118:Enhanced monitoring costs extra; CloudWatch metrics and logs are enough for dev
  count                      = local.is_primary ? 1 : 0
  identifier                 = "${local.name}-writer"
  cluster_identifier         = aws_rds_cluster.primary[0].id
  instance_class             = "db.serverless"
  engine                     = aws_rds_cluster.primary[0].engine
  engine_version             = aws_rds_cluster.primary[0].engine_version
  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true
}

# Phase 7: wraps the existing Mumbai cluster into a global database.
resource "aws_rds_global_cluster" "this" {
  count                        = local.global ? 1 : 0
  global_cluster_identifier    = "${var.project}-global"
  source_db_cluster_identifier = aws_rds_cluster.primary[0].arn
  force_destroy                = true # destroying the global cluster detaches members instead of failing
  deletion_protection          = false
}

# ---------------------------------------------------------------------------
# DR secondary (dr workspace). No database name or credentials: everything, including the
# "app" role and its rds_iam grant, is replicated from Mumbai at the storage layer.
# ---------------------------------------------------------------------------
resource "aws_rds_cluster" "secondary" {
  #checkov:skip=CKV_AWS_139:Deletion protection off in dev so the drill can be destroyed
  #checkov:skip=CKV2_AWS_27:Same logging parameter group as the primary
  #checkov:skip=CKV2_AWS_8:Recovery for the secondary is the global database itself
  #checkov:skip=CKV_AWS_128:IAM authentication is enabled (iam_database_authentication_enabled)
  count                     = local.is_primary ? 0 : 1
  cluster_identifier        = local.name
  engine                    = "aurora-postgresql"
  engine_mode               = "provisioned"
  engine_version            = local.primary.aurora_engine_version
  global_cluster_identifier = local.primary.global_cluster_id

  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.data.arn

  copy_tags_to_snapshot           = true
  deletion_protection             = false
  skip_final_snapshot             = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = local.min_acu
    max_capacity = var.aurora_max_acu
  }

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "dr" {
  #checkov:skip=CKV_AWS_353:Performance Insights costs extra; enable in prod
  #checkov:skip=CKV_AWS_118:Enhanced monitoring costs extra
  count                      = local.is_primary ? 0 : var.dr_instances
  identifier                 = "${local.name}-reader-${count.index}"
  cluster_identifier         = aws_rds_cluster.secondary[0].id
  instance_class             = "db.serverless"
  engine                     = aws_rds_cluster.secondary[0].engine
  engine_version             = aws_rds_cluster.secondary[0].engine_version
  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true
}
