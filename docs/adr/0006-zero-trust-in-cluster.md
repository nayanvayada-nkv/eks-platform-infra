# ADR 0006: Zero Trust inside the cluster (Kyverno CEL policies, Istio ambient, NetworkPolicy)

- Status: accepted (code written 27 Nov 2026, not applied)
- Context: Phase 3 of the roadmap. Proof: "unsigned image rejected". The diagram shows Kyverno,
  Istio mTLS + AuthZ and NetworkPolicy. Cluster is small and cost-sensitive (2x t3.medium + Karpenter).
- Decisions:
  1. **Kyverno 1.20 with the new CEL policy types** (`ValidatingPolicy`, `ImageValidatingPolicy`,
     `policies.kyverno.io/v1`). The old `ClusterPolicy` type is deprecated in 1.20 and will be removed,
     so new code starts on the replacement.
  2. **Signature check against the KMS key reference** (`awskms:///alias/eks-platform-cosign`), not a
     public key pasted into Git. Kyverno's admission controller reads the public key and ECR signatures
     through Pod Identity (read-only ECR on `eks-platform/*`, `kms:GetPublicKey` on the key matched by
     alias). Trade-off: admission depends on KMS being reachable; with `failurePolicy: Fail` an outage
     means no new pods (fail closed). The alternative (public key in Git) removes that dependency but
     needs a commit whenever the key changes. This supersedes the "exported public key" note in ADR 0005.
  3. **The image policy also requires the signed SBOM attestation**, so "built by our pipeline" means
     tested, scanned, SBOM'd and signed, not just signed.
  4. **Registry + digest policy next to the signature policy.** The signature policy only matches our
     ECR; without the registry policy a Docker Hub image would simply not match and be allowed.
  5. **Opt-out scope:** policies apply to every namespace except a short system list. New namespaces are
     covered automatically, and a namespace policy forces PSA `restricted` + ambient labels on them.
  6. **Istio ambient mode, not sidecars.** ztunnel (one per node) gives mTLS and L4 AuthorizationPolicy.
     Sidecars would add a proxy to every pod (CPU/memory on a small cluster) and need `NET_ADMIN` init
     containers that conflict with PSA `restricted`. L7 rules (paths, JWT) need a waypoint proxy later.
  7. **Mesh-wide `PeerAuthentication` STRICT.** Plaintext to meshed pods is refused. Consequence: Phase 4/5
     traffic from the ALB must enter through an Istio ingress gateway, not straight to the pods.
  8. **NetworkPolicy enforced by the VPC CNI** (`enableNetworkPolicy`), default deny per namespace.
     It must allow HBONE (TCP 15008) for mesh traffic and the probe address 169.254.7.127 used by ambient.
  9. **Everything Phase 3 is installed by Argo CD** in sync waves (Kyverno + Istio base, then istiod/cni,
     then ztunnel, then policies, then apps). A custom health check for `Application` makes waves wait.
- Consequences: about 6 extra pods plus 2 DaemonSets (may make Karpenter add one small node in dev);
  dev runs one replica of each controller, prod needs 3 Kyverno admission replicas. Secrets management
  (External Secrets + Secrets Manager) moves to Phase 4, where the first real secret (database) appears.
