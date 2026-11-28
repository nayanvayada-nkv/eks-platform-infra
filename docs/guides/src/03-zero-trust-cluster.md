# Phase 3 Guide: Zero Trust Inside the Cluster

<div class="cover" markdown>
<p class="sub">Kyverno admission policies, Istio ambient mTLS, AuthorizationPolicy, NetworkPolicy, Pod Security.</p>
<span class="status">Written and validated as code &middot; not yet run on AWS</span>
</div>

<div class="story" markdown>
Inside QuickCart's warehouse, staff wear **ID badges**, every **door checks the badge**, conversations
between departments happen in **sealed envelopes**, and the **receiving dock** refuses any box without the
company seal. Even someone who sneaks in through a window cannot walk into the cash office.
</div>

## 1. Four controls, four questions

| Control | Question it answers | Where |
|---|---|---|
| Pod Security (restricted) | Is this pod asking for dangerous powers (root, privileged, host access)? | namespace labels |
| Kyverno | Is this image ours, pinned by digest, signed, with a signed SBOM? Does it declare resources? | `gitops/platform/zero-trust` |
| Istio ambient (ztunnel) | Who is calling (cryptographic identity)? Is the traffic encrypted? | `gitops/clusters/dev/templates/istio.yaml` |
| NetworkPolicy | Is this IP/port allowed to talk to that pod at all? | `gitops/workloads/backend/network` |

[[diagram:admission]]

## 2. Kyverno: the receiving dock
<div class="simple" markdown>
Kyverno is an **admission controller**: Kubernetes asks it "may I create this pod?" before doing it.
Our policies say no to images from other registries, to tags instead of digests, to unsigned images,
to images without a signed SBOM, and to containers without CPU/memory requests and a memory limit.
New namespaces must opt in to Pod Security "restricted" and the mesh.
</div>

| Policy (CEL, Kyverno 1.20) | Rule |
|---|---|
| `verify-image-signatures` (ImageValidatingPolicy) | Cosign signature with our KMS key + signed SPDX SBOM; digest required |
| `restrict-image-registries` | Only `<account>.dkr.ecr.<region>.amazonaws.com/eks-platform/`, by digest |
| `require-resources` | `requests.cpu`, `requests.memory`, `limits.memory` on every container |
| `require-namespace-guardrails` | Namespace labels: PSA `restricted`, `istio.io/dataplane-mode: ambient` |

<div class="deep" markdown>
**Fail closed:** `failurePolicy: Fail`. If Kyverno cannot check (KMS or ECR unreachable, Kyverno down),
new pods in app namespaces are refused. Running pods keep running. **Opt-out scope:** every namespace is
checked except a short system list, so a forgotten new namespace is protected by default.
Kyverno 1.20 deprecates the old `ClusterPolicy` type, so the policies use the new CEL types.
</div>

```yaml
validations:
  - expression: "variables.images.all(i, i.startsWith('123456789012.dkr.ecr.ap-south-1.amazonaws.com/eks-platform/'))"
    messageExpression: "'images must come from ..., got: ' + variables.images.filter(...).join(', ')"
  - expression: "variables.images.all(i, i.contains('@sha256:'))"
```

## 3. Istio ambient: badges and sealed envelopes
[[diagram:mesh]]
<div class="simple" markdown>
A **service mesh** gives every workload an identity (based on its Kubernetes service account) and
encrypts traffic between workloads with **mutual TLS**: both sides prove who they are. In **ambient
mode**, a small proxy called **ztunnel** runs once per node instead of a sidecar in every pod.
</div>

| | Sidecars (classic Istio) | Ambient (chosen) |
|---|---|---|
| Proxies | One Envoy per pod | One ztunnel per node (+ optional waypoint for L7) |
| Cost on a small cluster | High (CPU/memory per pod) | Low |
| Pod Security restricted | Init container needs NET_ADMIN (conflict) | Works (istio-cni handles redirection) |
| Jobs | Sidecar keeps Jobs running | Jobs finish normally |
| L7 rules (paths, JWT) | Yes | Needs a waypoint proxy (not deployed yet) |

`PeerAuthentication` STRICT (mesh-wide) refuses plaintext to meshed pods. The backend's
`AuthorizationPolicy` allows only the ingress gateway and the backend itself on port 8080 (and later
Prometheus on 9464).

## 4. NetworkPolicy: who may talk at all
Default deny in both directions, then explicit allows: DNS to CoreDNS, HBONE (15008) from the gateway
namespace, kubelet probes from `169.254.7.127` (ambient rewrites probe sources), and later database,
cache, Pod Identity agent and VPC endpoints. Enforced by the VPC CNI's eBPF agent
(`enableNetworkPolicy=true`, otherwise policies are silently ignored).

<div class="bug" markdown>
Kustomize `labels` with `includeSelectors: true` also rewrote the NetworkPolicy selectors: default-deny
would have covered only labelled pods and the DNS rule would have pointed to pods labelled "backend" in
kube-system, blocking DNS entirely. Found by rendering and reading the output; fixed by moving the network
rules out of the labelled base.
</div>

<div class="why" markdown>
Two independent checks on every call: NetworkPolicy by address, Istio by cryptographic identity. Spoofing
an IP does not give you a certificate, and a valid certificate does not open a blocked port.
</div>

## 5. How to switch it on and demo it
Argo CD installs it all in waves (Kyverno + Istio base -> istiod/cni -> ztunnel -> policies -> apps). Demos:
```bash
kubectl -n backend run nginx --image=nginx:1.29             # refused: images must come from ...
kubectl create namespace scratch                             # refused: needs PSA restricted label
kubectl -n backend run unsigned --image=$REG/backend@<digest-of-unsigned>   # refused: not signed
kubectl apply -f docs/runbooks/phase3-demo-client.yaml       # cross-namespace call times out
```

## 6. Common mistakes
| Mistake | Effect | Here |
|---|---|---|
| Kyverno policies in Audit forever | Nothing is actually blocked | `validationActions: [Deny]` |
| Checking only some namespaces (opt-in) | New namespaces unprotected | Opt-out with a short system list |
| Strict mTLS but ALB talks to pods directly | Traffic fails | ALB -> Istio gateway (Phase 4/5) |
| NetworkPolicy without CNI support | Policies silently ignored | VPC CNI `enableNetworkPolicy` |

## 7. Interview questions
**Why both NetworkPolicy and Istio AuthZ?** Defence in depth: L3/L4 address rules plus identity rules.

**What if Kyverno goes down?** New app pods are refused (fail closed); run 3 replicas in prod.

**Why ambient?** Lower cost, compatible with restricted pods, Jobs complete; add a waypoint when L7 rules are needed.

<div class="glossary" markdown>
**Glossary.** *Admission controller*: code that approves or rejects API requests. *CEL*: Common
Expression Language used by Kubernetes and Kyverno policies. *mTLS*: TLS where both sides present
certificates. *SPIFFE ID*: identity like `spiffe://cluster.local/ns/backend/sa/backend`. *HBONE*: Istio's
mTLS tunnel on port 15008.
</div>

## Test yourself
1. Which four checks must an image pass to run in `backend`?
2. Why is a Docker Hub image refused even though the signature policy only matches our ECR?
3. What does ztunnel do, and where does it run?
4. Why does the NetworkPolicy allow `169.254.7.127`?

<div class="evidence" markdown>
Denial messages for the unsigned image and Docker Hub image, `kubectl -n argocd get applications`
all Healthy, ztunnel metrics showing mutual TLS connections.
</div>
