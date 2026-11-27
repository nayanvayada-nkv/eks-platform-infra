# ---------------------------------------------------------------------------
# Aurora PostgreSQL Serverless v2 ("Aurora" in the diagram). Scales to 0 ACU when idle,
# so dev pays mainly for storage. Later, pgvector on this same database is the
# recommended vector store (roadmap Phase 9).
# ---------------------------------------------------------------------------
data "aws_rds_engine_version" "postgres" {
  engine  = "aurora-postgresql"
  version = var.aurora_postgres_major
  latest  = true
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

resource "aws_rds_cluster" "this" {
  #checkov:skip=CKV_AWS_139:Deletion protection is a variable; off in dev so the test run can be destroyed
  #checkov:skip=CKV2_AWS_27:Logs DDL and slow queries (parameter group); logging every statement would copy user data into logs
  #checkov:skip=CKV2_AWS_8:AWS Backup plans come with Phase 7 (DR); Aurora automated backups are on
  cluster_identifier = local.name
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" # Serverless v2 runs on the provisioned engine mode
  engine_version     = data.aws_rds_engine_version.postgres.version_actual
  database_name      = var.database_name

  # The admin password is generated and rotated by RDS in Secrets Manager (encrypted with our key).
  # Nobody types it, nothing in Git or Terraform state holds it. Only the db-migrate job reads it.
  master_username               = "dbadmin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.data.arn

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
    min_capacity             = 0
    max_capacity             = var.aurora_max_acu
    seconds_until_auto_pause = var.aurora_auto_pause_seconds
  }
}

resource "aws_rds_cluster_instance" "writer" {
  #checkov:skip=CKV_AWS_353:Performance Insights costs extra; enable in prod
  #checkov:skip=CKV_AWS_118:Enhanced monitoring costs extra; CloudWatch metrics and logs are enough for dev
  identifier                 = "${local.name}-writer"
  cluster_identifier         = aws_rds_cluster.this.id
  instance_class             = "db.serverless"
  engine                     = aws_rds_cluster.this.engine
  engine_version             = aws_rds_cluster.this.engine_version
  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true
}
