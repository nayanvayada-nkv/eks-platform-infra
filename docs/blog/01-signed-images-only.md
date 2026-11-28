# Draft: "Only signed images may run" — a supply chain you can prove on EKS

*Draft blog post. Replace every [measure] with numbers from the run day before publishing.*

**The problem.** Most clusters will run any image someone can reference. An attacker (or a tired
engineer) only needs `kubectl run` or a bad Helm value to put unreviewed code next to production data.

**The chain I built**
1. CI (GitHub Actions, OIDC, no stored AWS keys) tests, builds, scans with Trivy (fixable HIGH/CRITICAL
   blocks the build), creates an SPDX SBOM, pushes to ECR **by digest**, signs the digest with Cosign
   using a key that never leaves AWS KMS, and attaches the signed SBOM.
2. CI never deploys. It opens a pull request that changes one digest in Git. Merging is the approval.
3. Argo CD syncs. Kyverno (CEL `ImageValidatingPolicy`) checks at admission: our ECR only, digest only,
   signed by our KMS key, signed SBOM present. Anything else is refused, and it fails closed.

**Proof:** an image built on my laptop and pushed to the same ECR is refused with
`image is not signed with the project Cosign key` ([screenshot]).

**Lessons:** ECR immutable tags broke Cosign re-signing until I excluded `sha256-*` tags; a Kustomize
image override silently dropped the digest (and Kyverno caught it); new Kyverno CEL policy types replace
the deprecated `ClusterPolicy`. Cost: [measure].

**What I would change at company scale:** a central signing service per org, keyless signing with
Sigstore for open source, policy exceptions with expiry, and admission metrics on a shared dashboard.
