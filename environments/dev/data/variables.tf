variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aurora_postgres_major" {
  description = "Aurora PostgreSQL major version; the latest minor is picked at plan time. pgvector (Phase 9) ships with it."
  type        = string
  default     = "17"
}

variable "aurora_max_acu" {
  description = "Serverless v2 ceiling in ACUs (1 ACU ~ 2 GiB RAM). Cost guard rail."
  type        = number
  default     = 2
}

variable "aurora_auto_pause_seconds" {
  description = "Idle time before Aurora scales to 0 ACU (compute stops billing; storage still bills)."
  type        = number
  default     = 300
}

variable "deletion_protection" {
  description = "Dev: false so the test run can be destroyed. Prod: true."
  type        = bool
  default     = false
}

variable "database_name" {
  type    = string
  default = "app"
}

variable "app_db_user" {
  description = "PostgreSQL role the backend logs in as, with an IAM token (no password). Created by the db-migrate job."
  type        = string
  default     = "app"
}

variable "app_namespace" {
  type    = string
  default = "backend"
}
