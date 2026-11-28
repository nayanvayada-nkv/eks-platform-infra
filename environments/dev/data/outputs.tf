# Non-secret connection settings, passed to the backend through Argo CD (platform stack).
output "backend_config" {
  description = "Becomes the backend-config ConfigMap. Contains no secrets."
  value = {
    AWS_REGION      = var.aws_region
    DB_HOST         = local.cluster.endpoint # regional writer endpoint (DR: writable after failover)
    DB_PORT         = tostring(local.cluster.port)
    DB_NAME         = var.database_name
    DB_USER         = var.app_db_user
    DB_ADMIN_SECRET = local.admin_secret_arn
    CACHE_HOST      = aws_elasticache_serverless_cache.this.endpoint[0].address
    CACHE_PORT      = tostring(aws_elasticache_serverless_cache.this.endpoint[0].port)
    CACHE_NAME      = aws_elasticache_serverless_cache.this.name
    CACHE_USER      = aws_elasticache_user.app.user_id
    EMBED_MODEL     = var.embedding_model_id
  }
}

output "aurora_engine_version" {
  value = local.cluster.engine_version
}

# Read by the DR (secondary) data stack and by scripts/dr-drill.sh.
output "global_cluster_id" {
  value = local.global ? aws_rds_global_cluster.this[0].id : ""
}

output "cluster_arn" {
  value = local.cluster.arn
}

output "admin_secret_arn" {
  value = local.admin_secret_arn
}

output "data_key_dr_replica_arn" {
  value = local.global ? aws_kms_replica_key.data_dr[0].arn : ""
}
