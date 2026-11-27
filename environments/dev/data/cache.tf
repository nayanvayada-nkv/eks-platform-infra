# ---------------------------------------------------------------------------
# ElastiCache Serverless for Valkey ("Redis" in the diagram). Valkey is the open-source
# Redis fork AWS prices lower; same protocol, so the app uses the redis client.
# TLS is always on for serverless caches; login is by IAM token, not a shared password.
# ---------------------------------------------------------------------------

# ElastiCache needs a user called "default" in every user group. Ours can never log in.
resource "aws_elasticache_user" "default" {
  user_id       = "${local.name}-default"
  user_name     = "default"
  engine        = "valkey"
  access_string = "off -@all"

  authentication_mode {
    type = "no-password-required" # irrelevant: the user is "off"
  }
}

# For IAM authentication the user id and user name must be identical.
resource "aws_elasticache_user" "app" {
  user_id   = "${local.name}-app"
  user_name = "${local.name}-app"
  engine    = "valkey"
  # Least privilege: only keys under "backend:", read/write commands, no admin or
  # dangerous commands (FLUSHALL, CONFIG, KEYS...).
  access_string = "on ~backend:* -@all +@read +@write +@connection -@dangerous"

  authentication_mode {
    type = "iam"
  }
}

resource "aws_elasticache_user_group" "this" {
  user_group_id = "${local.name}-users"
  engine        = "valkey"
  user_ids      = [aws_elasticache_user.default.user_id, aws_elasticache_user.app.user_id]
}

resource "aws_elasticache_serverless_cache" "this" {
  name                 = local.name
  engine               = "valkey"
  major_engine_version = "8"
  description          = "Backend cache (dev)"
  kms_key_id           = aws_kms_key.data.arn
  subnet_ids           = local.network.private_subnet_ids
  security_group_ids   = [aws_security_group.cache.id]
  user_group_id        = aws_elasticache_user_group.this.user_group_id

  snapshot_retention_limit = 1
  daily_snapshot_time      = "21:00"

  # Cost guard rails: serverless bills per GB stored and per ECPU used.
  cache_usage_limits {
    data_storage {
      maximum = 1
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 1000
    }
  }
}
