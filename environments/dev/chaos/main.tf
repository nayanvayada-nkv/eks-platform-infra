# ---------------------------------------------------------------------------
# Game day (Phase 8): AWS Fault Injection Service experiment templates. Optional stack, not
# in up-dev.sh; apply it for a game day, start experiments by hand, destroy it afterwards.
# Templates cost nothing until an experiment runs (billed per action-minute).
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "chaos"
    }
  }
}

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

data "aws_iam_policy_document" "fis_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fis" {
  name               = "${var.project}-${var.environment}-fis"
  assume_role_policy = data.aws_iam_policy_document.fis_assume.json
}

# AWS-managed policy for EC2 fault actions (stop/terminate/spot interruption on targeted instances).
resource "aws_iam_role_policy_attachment" "fis_ec2" {
  role       = aws_iam_role.fis.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access"
}

# 1. Spot interruption of one Karpenter node: Karpenter must cordon, drain and replace it
#    within the 2-minute warning, and the backend must stay within its SLO.
resource "aws_fis_experiment_template" "spot_interruption" {
  description = "Send a spot interruption to one Karpenter node"
  role_arn    = aws_iam_role.fis.arn
  tags        = { Name = "${var.project}-${var.environment}-spot-interruption" }

  stop_condition {
    source = "none" # short, single-node experiment; watch the SLO dashboard and stop it by hand if needed
  }

  action {
    name      = "interrupt-one-spot-node"
    action_id = "aws:ec2:send-spot-instance-interruptions"
    parameter {
      key   = "durationBeforeInterruption"
      value = "PT2M"
    }
    target {
      key   = "SpotInstances"
      value = "karpenter-spot"
    }
  }

  target {
    name           = "karpenter-spot"
    resource_type  = "aws:ec2:spot-instance"
    selection_mode = "COUNT(1)"
    resource_tag {
      key   = "karpenter.sh/nodepool"
      value = "default"
    }
    filter {
      path   = "State.Name"
      values = ["running"]
    }
  }
}

# 2. Lose one system node (CoreDNS, controllers, Argo CD may run there): the managed node
#    group must replace it and the PodDisruption/replica settings must keep the platform up.
resource "aws_fis_experiment_template" "system_node_loss" {
  description = "Terminate one managed system node"
  role_arn    = aws_iam_role.fis.arn
  tags        = { Name = "${var.project}-${var.environment}-system-node-loss" }

  stop_condition {
    source = "none"
  }

  action {
    name      = "terminate-one-system-node"
    action_id = "aws:ec2:terminate-instances"
    target {
      key   = "Instances"
      value = "system-node"
    }
  }

  target {
    name           = "system-node"
    resource_type  = "aws:ec2:instance"
    selection_mode = "COUNT(1)"
    resource_tag {
      key   = "eks:nodegroup-name"
      value = "system"
    }
    filter {
      path   = "State.Name"
      values = ["running"]
    }
  }
}

output "start_commands" {
  value = {
    spot_interruption = "aws fis start-experiment --experiment-template-id ${aws_fis_experiment_template.spot_interruption.id}"
    system_node_loss  = "aws fis start-experiment --experiment-template-id ${aws_fis_experiment_template.system_node_loss.id}"
  }
}
