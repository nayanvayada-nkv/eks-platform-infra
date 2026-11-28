# ---------------------------------------------------------------------------
# Argo CD (diagram: "Argo CD hub"). Pull-based GitOps: the cluster pulls from Git,
# CI never gets cluster credentials. UI is not exposed; use:
#   kubectl -n argocd port-forward svc/argocd-server 8080:443
# ---------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  wait             = true
  timeout          = 600

  values = [yamlencode({
    dex           = { enabled = false } # local admin for dev; SSO later
    notifications = { enabled = false }
    configs = {
      cm = {
        "admin.enabled"           = "true"  # local admin for dev only; SSO in prod
        "users.anonymous.enabled" = "false" # no read-only access without login
        "exec.enabled"            = "false" # no shell into pods from the UI
      }
    }
    server = {
      service = { type = "ClusterIP" }
    }
  })]

  depends_on = [helm_release.karpenter] # Argo CD pods may land on Karpenter nodes
}

# Root "app of apps": renders gitops/clusters/dev (a small Helm chart of Applications).
resource "kubectl_manifest" "argocd_root_app" {
  count = var.gitops_repo_url == "" ? 0 : 1

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root-dev"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_revision
        path           = "gitops/clusters/dev"
        helm = {
          valuesObject = {
            repoURL        = var.gitops_repo_url
            targetRevision = var.gitops_revision
          }
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
      }
    }
  })

  depends_on = [helm_release.argocd]
}
