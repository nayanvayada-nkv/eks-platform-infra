variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "state_region" {
  description = "Region of the Terraform state bucket (Mumbai), also when this stack runs in the dr workspace."
  type        = string
  default     = "ap-south-1"
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

variable "role" {
  description = "primary = Mumbai writer (default workspace). secondary = Frankfurt DR copy of the Aurora global database (dr workspace)."
  type        = string
  default     = "primary"

  validation {
    condition     = contains(["primary", "secondary"], var.role)
    error_message = "role must be primary or secondary."
  }
}

variable "dr_region" {
  description = "Primary only. A DR region (e.g. eu-central-1) turns the cluster into an Aurora Global Database, replicates the admin secret and the data key there. Empty = single region."
  type        = string
  default     = ""
}

variable "dr_instances" {
  description = "Secondary only. 0 = headless pilot light (storage replicated, no compute, cheapest). 1 = a reader that can take over as writer."
  type        = number
  default     = 0
}

variable "admin_password_version" {
  description = "Bump to generate and write a new Aurora admin password (it is never stored in Terraform state)."
  type        = number
  default     = 1
}

variable "embedding_model_id" {
  description = "Bedrock embedding model for RAG (Phase 9). Titan Text Embeddings V2, 1024 dimensions."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}
