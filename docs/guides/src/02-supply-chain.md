# Phase 2 Guide: Supply Chain (build, scan, sign, deploy by digest)

<div class="cover" markdown>
<p class="sub">GitHub Actions, Trivy, SBOM, ECR, Cosign with a KMS key, GitOps pull requests and Argo CD.</p>
<span class="status">Written and validated as code &middot; not yet run on AWS</span>
</div>

<div class="story" markdown>
Every QuickCart meal is cooked in a central kitchen, checked by a food inspector, labelled with an
ingredient list, sealed with a tamper-proof company seal, and only sealed boxes are accepted at the
stores. A box without the seal, or with a broken one, is refused at the door, even if it looks fine.
</div>

[[diagram:flow_deploy]]

## 1. The idea in simple words
<div class="simple" markdown>
A **container image** is a packaged app. The supply chain makes sure the image that runs is exactly the
one our pipeline built and checked. We **scan** it for known vulnerabilities (Trivy), **list** everything
inside (SBOM), store it by its unique fingerprint (**digest**), and **sign** that fingerprint with a key
that lives in AWS KMS. The cluster later checks the signature before running it (Phase 3).
</div>

## 2. Each step, what and why

| Step | Tool / file | What | Security reason |
|---|---|---|---|
| Tests | `pytest` | Code works | Broken code never gets built |
| Build | `apps/backend/Dockerfile` | Multi-stage, ECR Public base, non-root uid 10001, read-only root FS, pip removed | Smaller attack surface, no Docker Hub |
| Scan | Trivy | Fails on fixable HIGH/CRITICAL | Known holes never ship |
| SBOM | Syft (SPDX) | List of every package | Answer "are we affected by CVE-X?" in minutes |
| Push | ECR, immutable tags | Stored by digest | A tag cannot be re-pointed to other content |
| Sign | Cosign + KMS key | Signs the digest, attaches signed SBOM | Proves *who* built it; private key never leaves KMS |
| Propose | `create-pull-request` | PR changing one digest in `gitops/` | A human approves every deploy |
| Deploy | Argo CD | Pulls Git, applies to cluster | CI never holds cluster credentials |

[[diagram:supply_chain_trust]]

## 3. Tags vs digests
<div class="deep" markdown>
`backend:v1` is a **tag**: a movable label. `backend@sha256:3f1a...` is a **digest**: a hash of the
image content. If even one byte changes, the digest changes. We deploy and sign by digest, so what was
scanned is exactly what runs. ECR tags are immutable except Cosign's own `sha256-*.sig/.att` tags,
which must be updatable to add signatures (we found this the hard way, see below).
</div>

## 4. GitOps and Argo CD
<div class="simple" markdown>
**GitOps** = Git is the single source of truth for what runs. Argo CD inside the cluster keeps comparing
Git with the cluster and fixes drift ("self-heal"). Deploy = merge a PR. **Rollback = `git revert`.**
</div>

The **app of apps**: one root Application (created by Terraform) renders `gitops/clusters/dev`, a small
Helm chart whose templates are more Applications (Kyverno, Istio, observability, backend...). Sync waves
order them, and a custom health check makes Argo CD wait for each wave.

## 5. Walk-through of the real pipeline

The publish guard in `.github/workflows/backend-image.yml`:

```yaml
PUBLISH: ${{ github.event_name != 'pull_request' && github.ref == 'refs/heads/main'
             && vars.AWS_BUILD_ROLE_ARN != '' }}
```

<div class="simple" markdown>
Pull requests build, test, scan and create the SBOM, but never touch AWS. Only `main`, and only once the
AWS side exists, pushes and signs. This keeps untrusted PR code away from the signing key.
</div>

The signing step:

```bash
cosign sign --yes --key "awskms:///alias/eks-platform-cosign" \
  --new-bundle-format=false --use-signing-config=false "$REF"      # REF = image@sha256:...
cosign attest --yes --key "$COSIGN_KEY" --type spdxjson --predicate sbom.spdx.json "$REF"
cosign verify --key "$COSIGN_KEY" "$REF" > /dev/null               # prove it before moving on
```

The GitOps bump: `kustomize edit set image backend=<ecr>/eks-platform/backend@<digest>` in
`gitops/workloads/backend/overlays/dev`, committed on branch `gitops/backend-dev` and opened as a PR.

## 6. Common mistakes

| Mistake | Risk | Here |
|---|---|---|
| Deploying `:latest` | Different code on every node, no rollback | Digest only, enforced by Kyverno |
| CI with `kubectl` access | Stolen CI token = cluster takeover | CI only writes to Git |
| Signing key in a GitHub secret | Key can be exfiltrated | Key in KMS, usable only via IAM |
| Scanning but not failing | Vulnerable images still ship | Trivy exit code 1 on fixable HIGH/CRITICAL |
| Unpinned third-party actions | A hijacked tag runs in your pipeline | Pinned by commit SHA + Dependabot |

## 7. Interview questions with short answers

**Push vs pull deployments?** Push (CI runs kubectl) needs cluster credentials in CI. Pull (Argo CD
pulls Git) keeps credentials inside the cluster and corrects drift.

**Keyless or KMS signing?** Keyless (Sigstore + OIDC) is great for open source; KMS keeps signing inside
our account with IAM control and CloudTrail audit, which suits a company platform.

**What if Trivy blocks a release you need today?** Fix or upgrade the package; if truly unfixable and
accepted, document an expiring exception (`.trivyignore` with a reason), never disable the gate.

## 8. How to switch it on
1. Apply `environments/shared/supply-chain` (ECR, Cosign key, build role).
2. GitHub: set variable `AWS_BUILD_ROLE_ARN`; allow Actions to create pull requests.
3. Merge a change under `apps/backend/` -> watch the workflow -> merge the PR it opens.
4. Verify: `cosign verify --key awskms:///alias/eks-platform-cosign <image@digest>`.

<div class="bug" markdown>
(1) ECR fully immutable tags blocked Cosign from writing signature tags -> `IMMUTABLE_WITH_EXCLUSION`
for `sha256-*`. (2) Trivy found 6 HIGH issues in pip's vendored libraries -> pip removed from the image,
OS packages upgraded. (3) `sigstore/cosign-installer@v4` was not a real tag -> pinned by SHA to v4.1.4
(Phase 8). All three would have broken the first real run.
</div>

<div class="why" markdown>
Signing with a KMS key means the signing key cannot be copied, only *used*, and only by the build role
from `main`. Every use is in CloudTrail. Actions are pinned by commit SHA so a hijacked tag cannot
inject code into the pipeline that signs images.
</div>

<div class="glossary" markdown>
**Glossary.** *CVE*: a published vulnerability. *SBOM*: software bill of materials. *Cosign*: Sigstore's
signing tool. *Attestation*: a signed statement about an image (here: its SBOM). *OIDC*: login with
short-lived tokens instead of passwords. *Drift*: cluster state different from Git.
</div>

## Test yourself
1. Why sign the digest and not the tag?
2. What does the SBOM let you do the day a new critical CVE is announced?
3. Why does CI open a pull request instead of deploying?
4. How do you roll back a bad release in this design?
5. What happens if someone pushes an image to ECR from a laptop?

<div class="evidence" markdown>
Pipeline run (Trivy + Cosign steps), the auto-created GitOps PR, `cosign verify` output, ECR showing
`.sig` and `.att` tags, Argo CD Synced/Healthy.
</div>
