# Architecture Diagrams: Zero Trust EKS Platform

<div class="cover" markdown>
<p class="sub">Every picture of the platform in one place, each with a plain explanation.
Read this first; the phase guides go deep on each box.</p>
<span class="status">Written and validated as code &middot; not yet run on AWS &middot; evidence added after the run</span>
</div>

## How to read these guides

Each guide uses the same building blocks:

- **Real-life example (QuickCart):** a fictional shopping + food delivery app (think of a mix of an
  online store and a food delivery app). Every concept is first explained through it.
- **In simple words:** the idea without jargon. A fresher should understand this part.
- **Going deeper:** the real technical detail, file names and settings.
- **Security reason:** why the design is safer, in one or two sentences you can say in an interview.
- **Evidence (after the run):** dashed boxes that will hold screenshots and measured numbers.

[[diagram:quickcart]]

## 1. The whole platform on one page

[[diagram:arch_overall]]

<div class="simple" markdown>
Shoppers reach the app through **CloudFront** (a global front door) and the **WAF** (a security guard
that throws out known attacks). Behind it, the app runs as **pods** on **Amazon EKS** (managed
Kubernetes) in Mumbai. The app stores data in **Aurora** (database) and **Valkey** (fast cache), and asks
**Amazon Bedrock** (AI models) to answer support questions. Code reaches the cluster only through

**GitHub Actions** (build, scan, sign) and **Argo CD** (deploys what is in Git). A copy of the important
parts waits in **Frankfurt** in case Mumbai fails.
</div>

<div class="story" markdown>
QuickCart has a shop front (CloudFront), a guard at the door (WAF), a kitchen and warehouse behind a
locked door (EKS in private subnets), a ledger (Aurora), a quick-reference board for popular items
(Valkey), and a help desk that reads the policy binder before answering (Bedrock RAG). Only stock that
passed quality control and carries the company seal (Cosign signature) may enter the warehouse.
</div>

## 2. Security in layers

[[diagram:arch_layers]]

<div class="simple" markdown>
"Zero Trust" means **no part trusts another just because it is inside the network**. Every hop checks
who is calling and whether it is allowed. Layers matter because one mistake (an open port, a leaked
image) should not be enough for an attacker.
</div>

## 3. One request, hop by hop

[[diagram:flow_request]]

| Hop | What it checks | Phase |
|---|---|---|
| CloudFront + WAF | HTTPS only; attack patterns (XSS, SQL injection, Log4j); too many requests from one IP | 5 |
| Internal ALB | Reachable only from CloudFront's VPC origin, never from the internet | 5 |
| Istio gateway + ztunnel | Encrypts traffic (mTLS); only allowed identities may call the backend | 3, 4 |
| NetworkPolicy | Default deny; only listed sources and ports | 3 |
| Backend | Validates input; tenant from the API key (RAG) | 4, 9 |
| Aurora / Valkey / Bedrock | IAM tokens tied to the pod's identity; no passwords | 4, 9 |

## 4. How code gets to production

[[diagram:flow_deploy]]

<div class="why" markdown>
CI never has cluster credentials and nobody runs `kubectl apply`. The only way to change what runs is a
reviewed pull request in Git, and the cluster refuses any image that our pipeline did not sign.
</div>

## 5. Terraform stacks and their order

[[diagram:flow_stacks]]

<div class="simple" markdown>
The infrastructure is split into small **stacks**, each with its own state file. A mistake in one stack
cannot break another, and the cheap long-lived parts (state bucket, ECR, keys) survive when the
expensive dev parts are destroyed every evening.
</div>

<div class="pagebreak"></div>

## 6. Inside the cluster: admission and the mesh

[[diagram:admission]]

[[diagram:mesh]]

## 7. Data without passwords

[[diagram:data_access]]

## 8. The edge

[[diagram:edge]]

## 9. Observability and alerts

[[diagram:observability]]

## 10. Disaster recovery (Frankfurt)

[[diagram:dr]]

## 11. AI support assistant (RAG) and tenant isolation

[[diagram:rag]]

[[diagram:tenancy]]

<div class="evidence" markdown>
After the run: screenshot of `kubectl get nodes`, Argo CD applications all Healthy, the CloudFront URL
answering, the Grafana Backend SLO dashboard, and the DR drill output.
</div>
