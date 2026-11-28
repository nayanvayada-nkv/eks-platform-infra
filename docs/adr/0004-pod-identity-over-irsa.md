# ADR 0004: EKS Pod Identity for AWS access from pods

- Status: accepted
- Context: the roadmap said IRSA. EKS Pod Identity is now the AWS-recommended way: no per-cluster
  OIDC trust in every role, roles are reusable across clusters, and the current community Karpenter
  module supports only Pod Identity.
- Decision: Karpenter, the AWS Load Balancer Controller and the EBS CSI driver use Pod Identity.
  The cluster still has an OIDC provider so IRSA remains available for tools that need it.
- Consequences: the `eks-pod-identity-agent` add-on must be running before these pods start.
