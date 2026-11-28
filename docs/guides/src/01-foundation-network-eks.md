# Phase 0 + 1 Guide: Foundation, Network and EKS

<div class="cover" markdown>
<p class="sub">Bootstrap (state, OIDC), the VPC, the EKS cluster, Karpenter and Pod Identity.</p>
<span class="status">Phase 0 applied once (later destroyed) &middot; Phase 1 written and validated, not yet run on AWS</span>
</div>

<div class="story" markdown>
Before QuickCart can open, it needs a **land registry** (where every building plan is recorded), a
**plot of land with fences and gates** (the network), a **building with a manager** (the Kubernetes
cluster), **permanent staff** for the basics (system nodes) and an **agency that sends extra workers at
rush hour** (Karpenter). Each worker gets a **badge that opens only the doors they need** (Pod Identity).
</div>

## 1. Phase 0: the bootstrap

<div class="simple" markdown>
Terraform remembers what it built in a **state file**. If that file is lost or two people edit it at once,
infrastructure gets out of control. So the very first step creates a safe home for state: an S3 bucket
(versioned, encrypted with our own KMS key, private, TLS only) with S3-native locking. It also creates a
way for GitHub Actions to log in to AWS **without any stored password** (OIDC).
</div>

| File / resource | What | Why | Security reason |
|---|---|---|---|
| `bootstrap/main.tf` S3 bucket | Remote state | One shared truth for all stacks | Versioning (undo), KMS, public access blocked, TLS-only policy, `prevent_destroy` |
| KMS key | Encrypts state | State can contain sensitive values | Our key, rotation on, auditable in CloudTrail |
| GitHub OIDC provider + plan role | CI logs in to AWS | No long-lived AWS keys in GitHub | Trust limited to this repo; plan role is read-only |

<div class="deep" markdown>
OIDC flow: GitHub issues a short-lived signed token for a workflow run; AWS STS checks the token's
issuer, audience and the `sub` claim (`repo:<org>/eks-platform-infra:ref:refs/heads/main`) against the
role's trust policy and returns 1-hour credentials. Nothing secret is stored in GitHub.
</div>

## 2. Phase 1: the network (`environments/dev/network`)

[[diagram:flow_request]]

| Piece | What | Why |
|---|---|---|
| VPC `10.20.0.0/16` | Private address space | Room for pods (VPC CNI gives each pod a VPC IP) |
| 3 public subnets (/24) | NAT gateway, load balancer ENIs | Only things that must face the internet |
| 3 private subnets (/20) | Nodes, pods, databases | Nothing here has a public IP |
| 1 NAT gateway | Outbound internet for private subnets | One (not three) to save cost in dev |
| S3 gateway endpoint + interface endpoints | Private AWS API access | Traffic to S3, Secrets Manager, Bedrock never crosses the internet |
| VPC flow logs | Who talked to whom | Evidence for investigations |
| AZs pinned by zone ID | `aps1-az1..3` | A new AWS zone cannot change the layout silently |

<div class="why" markdown>
Workloads sit in private subnets: they can call out through NAT or endpoints, but nobody on the internet
can open a connection to them. The only inbound path is the edge (Phase 5).
</div>

## 3. The EKS cluster (`modules/eks`, `environments/dev/eks`)

<div class="simple" markdown>
**Kubernetes** runs containers and keeps them healthy. **EKS** is AWS running the Kubernetes "brain"
(control plane) for us. We provide the **nodes** (EC2 machines) where pods run.
</div>

| Setting | Value | Why |
|---|---|---|
| Version | 1.36, standard support | Extended support costs ~6x more per hour |
| API endpoint | Public **but only your IP /32**, plus private | kubectl from your laptop, nobody else |
| Authentication | Access entries (API mode) | AWS-native, no `aws-auth` ConfigMap to break |
| Secrets | Envelope-encrypted with our KMS key | A stolen etcd backup is unreadable |
| System nodes | 2x t3.medium, label `node-role/system=true` | Run CoreDNS, controllers, Karpenter |
| Launch template | IMDSv2 required, hop limit 1, encrypted gp3 | Pods cannot steal the node's AWS credentials |
| Add-ons | VPC CNI (+ NetworkPolicy), kube-proxy, Pod Identity agent, CoreDNS, EBS CSI | Ordered so networking is ready before nodes join |

<div class="warn" markdown>
IMDSv2 **hop limit 1** matters: the instance metadata service answers only the node itself, so a
compromised pod cannot ask it for the node role's credentials. This blocks a classic cloud attack.
</div>

## 4. Karpenter: workers on demand

<div class="story" markdown>
At 1 pm everyone orders lunch on QuickCart. Instead of paying 20 delivery riders all day, the agency
sends extra riders exactly when orders queue up, and sends them home when the rush ends.
</div>

Karpenter watches for pods that cannot be scheduled and launches the cheapest fitting EC2 instance
(spot first, on-demand fallback), then removes empty or under-used nodes (consolidation). The
`NodePool` has a hard **16 vCPU limit**: the main cost guard rail.

## 5. Pod Identity: a badge per workload

| | IRSA (older) | Pod Identity (chosen, ADR 0004) |
|---|---|---|
| Setup per role | OIDC trust policy naming the cluster | One association: cluster + namespace + service account -> role |
| Moving clusters (DR) | Edit trust policies | Re-create associations from the same code |
| Credentials | Web identity token in the pod | Agent on the node hands out temporary credentials |

<div class="why" markdown>
Each workload gets only its own permissions (Karpenter: EC2 + SQS; LB controller: ELB; backend: its
database user). A compromised pod cannot use another pod's rights or the node's.
</div>

## 6. Walk-through of the real code

The launch template for system nodes (`modules/eks/main.tf`), line by line:

```hcl
metadata_options {
  http_endpoint               = "enabled"   # keep the metadata service (the node needs it)
  http_tokens                 = "required"  # IMDSv2 only: every call needs a session token
  http_put_response_hop_limit = 1           # the token cannot travel one hop further, into a pod
}
block_device_mappings {
  device_name = "/dev/xvda"
  ebs { volume_type = "gp3", encrypted = true, delete_on_termination = true }
}
```

The Pod Identity association for the Load Balancer Controller (`environments/dev/eks/main.tf`):

```hcl
associations = {
  this = {
    cluster_name    = module.eks.cluster_name
    namespace       = "kube-system"                    # only this namespace...
    service_account = "aws-load-balancer-controller"   # ...and only this service account
  }
}
```

<div class="simple" markdown>
Read the association as a sentence: "pods that run as service account X in namespace Y of cluster Z
may use role R". Any other pod asking for those credentials gets nothing.
</div>

## 7. Common mistakes (and how this project avoids them)

| Mistake | What goes wrong | Here |
|---|---|---|
| One huge Terraform state | One typo can plan to destroy everything | Small stacks, one state each |
| API endpoint open to 0.0.0.0/0 | Anyone can try to log in to the cluster | Validation rejects 0.0.0.0/0; your IP only |
| Nodes in public subnets | Nodes reachable from the internet | Private subnets only |
| IMDSv1 / hop limit 2 | Pods steal node credentials | IMDSv2, hop 1 |
| Kubernetes in extended support | ~6x control-plane cost | `upgrade_policy = STANDARD`, version 1.36 |
| No cost cap on autoscaling | A bug launches 50 nodes | Karpenter 16 vCPU limit |

## 8. Interview questions with short answers

**Why separate state files per stack?** Smaller blast radius, faster plans, and long-lived parts
(state, ECR, keys) survive when dev is destroyed.

**How does CI log in to AWS?** GitHub OIDC: a short-lived signed token is exchanged for 1-hour role
credentials; the trust policy limits it to this repo and branch. No keys stored anywhere.

**What does Karpenter do better than Cluster Autoscaler?** It picks the instance type per pending pods
(no fixed node groups), favours spot, and consolidates under-used nodes quickly.

**What protects Kubernetes Secrets at rest?** Envelope encryption with our KMS key, on top of AWS's
default disk encryption.

## 9. How to switch it on (run day)

```bash
scripts/check-bootstrap.sh                 # state bucket and key exist
scripts/tf.sh environments/dev/network init && scripts/tf.sh environments/dev/network plan
scripts/tf.sh environments/dev/network apply   # after you read the plan
# same for environments/dev/eks, then:
aws eks update-kubeconfig --region ap-south-1 --name eks-platform-dev
kubectl get nodes -o wide                  # 2 system nodes Ready
```

## 10. Cost (dev, approximate)
EKS control plane ~$0.10/h, NAT ~$0.056/h + data, 2x t3.medium ~$0.09/h. About **$6-7 per day**, which
is why dev is destroyed after each session (`scripts/destroy-dev.sh`).

<div class="glossary" markdown>
**Glossary.** *VPC*: your private network in AWS. *Subnet*: a slice of it in one Availability Zone.
*NAT*: lets private machines call out without being reachable. *Node*: a machine running pods.
*Pod*: one or more containers scheduled together. *State file*: Terraform's record of what exists.
*Spot*: spare EC2 capacity, up to ~70-90% cheaper, can be taken back with a 2-minute notice.
</div>

## Test yourself
1. Why is the state bucket versioned and protected from deletion?
2. What attack does IMDSv2 with hop limit 1 prevent?
3. Why does the API endpoint allow only your IP, and what would you use in a company instead?
4. When would Karpenter launch an on-demand node instead of spot?
5. Name two differences between IRSA and Pod Identity.

<div class="evidence" markdown>
`kubectl get nodes -o wide` (system + Karpenter spot node), apply times per stack, cost for the day.
</div>
