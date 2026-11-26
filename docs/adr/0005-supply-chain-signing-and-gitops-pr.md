# ADR 0005: Cosign with a KMS key, digest pinning, and GitOps by pull request

- Status: accepted
- Context: the diagram requires signed images, deploy by digest, and Argo CD pulling from Git.
- Decisions:
  1. **Cosign key in AWS KMS** (ECC P-256, `SIGN_VERIFY`). The private key never leaves KMS; only the
     `main`-branch build role may call `kms:Sign`. Kyverno verifies with the exported public key (Phase 3).
     Keyless signing (Sigstore + GitHub OIDC) is the alternative; KMS keeps signing inside our account.
  2. **Legacy Cosign signature format** (`--new-bundle-format=false --use-signing-config=false`) so
     Kyverno and older verifiers can read it. Revisit when Kyverno is installed in Phase 3.
  3. **Deploy by digest, never by tag.** ECR tags are immutable as well.
  4. **CI opens a pull request** to bump the digest instead of pushing to `main`. Branch protection
     stays on, and merging the PR is the human deploy approval. CI never has cluster credentials.
- Consequences: one manual merge per deploy in dev (can be auto-merged later); KMS key costs $1/month.
