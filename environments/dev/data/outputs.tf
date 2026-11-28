# Non-secret connection settings, passed to the backend through Argo CD (platform stack).
output "backend_config" {
  description = "Becomes the backend-config ConfigMap. Contains no secrets."
  value = {
    AWS_REGION      = var.aws_region
    DB_HOST         = aws_rds_cluster.this.endpoint
    DB_PORT         = tostring(aws_rds_cluster.this.port)
    DB_NAME         = var.database_name
    DB_USER         = var.app_db_user
    DB_ADMIN_SECRET = aws_rds_cluster.this.master_user_secret[0].secret_arn
    CACHE_HOST      = aws_elasticache_serverless_cache.this.endpoint[0].address
    CACHE_PORT      = tostring(aws_elasticache_serverless_cache.this.endpoint[0].port)
    CACHE_NAME      = aws_elasticache_serverless_cache.this.name
    CACHE_USER      = aws_elasticache_user.app.user_id
  }
}

output "aurora_engine_version" {
  value = aws_rds_cluster.this.engine_version_actual
}
