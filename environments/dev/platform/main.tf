data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "nonprod/dev/ap-south-1/network/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "nonprod/dev/ap-south-1/eks/terraform.tfstate"
    region = var.aws_region
  }
}

# Phase 4: Aurora / Valkey endpoints for the backend (no secrets in these outputs).
data "terraform_remote_state" "data" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "nonprod/dev/ap-south-1/data/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  # Controllers run on the managed system nodes, never on nodes they manage.
  system_node_selector = { "node-role/system" = "true" }
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller: turns Ingress / Service into ALB / NLB
# ---------------------------------------------------------------------------
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_lb_controller_chart_version

  values = [yamlencode({
    clusterName  = local.eks.cluster_name
    region       = var.aws_region
    vpcId        = local.network.vpc_id
    nodeSelector = local.system_node_selector
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller" # bound to the IAM role by Pod Identity (eks stack)
    }
  })]
}

# ---------------------------------------------------------------------------
# metrics-server: CPU / memory metrics for the HPA ("HPA + Karpenter" in the diagram)
# ---------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  values = [yamlencode({
    nodeSelector = local.system_node_selector
  })]
}

# ---------------------------------------------------------------------------
# Karpenter: just-in-time nodes for workloads
# ---------------------------------------------------------------------------
resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version
  wait       = true

  values = [yamlencode({
    replicas     = 1 # dev; use 2 in prod
    nodeSelector = local.system_node_selector
    serviceAccount = {
      name = "karpenter" # bound to the IAM role by Pod Identity (eks stack)
    }
    settings = {
      clusterName       = local.eks.cluster_name
      interruptionQueue = local.eks.karpenter_queue_name
    }
    controller = {
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      role = local.eks.karpenter_node_role_name
      # Dev follows the latest AL2023 AMI. Pin a version (al2023@v2026xxxx) for prod.
      amiSelectorTerms           = [{ alias = "al2023@latest" }]
      subnetSelectorTerms        = [{ tags = { "karpenter.sh/discovery" = local.eks.cluster_name } }]
      securityGroupSelectorTerms = [{ tags = { "karpenter.sh/discovery" = local.eks.cluster_name } }]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpTokens              = "required"
        httpPutResponseHopLimit = 1
      }
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "30Gi"
          volumeType          = "gp3"
          encrypted           = true
          deleteOnTermination = true
        }
      }]
      tags = {
        Project     = var.project
        Environment = var.environment
        ManagedBy   = "karpenter"
      }
    }
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          expireAfter = "720h"
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
            # Dev: spot first (cheapest), on-demand as fallback.
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "t"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["4"] },
            { key = "karpenter.k8s.aws/instance-size", operator = "In", values = ["medium", "large", "xlarge"] },
          ]
        }
      }
      limits = { cpu = tostring(var.karpenter_cpu_limit) }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}
