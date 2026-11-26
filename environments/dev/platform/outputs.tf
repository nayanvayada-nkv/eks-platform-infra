output "aws_lb_controller_version" {
  value = helm_release.aws_lb_controller.version
}

output "karpenter_version" {
  value = helm_release.karpenter.version
}

output "argocd_version" {
  value = helm_release.argocd.version
}

output "argocd_access" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8080:443  (user admin, password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
}
