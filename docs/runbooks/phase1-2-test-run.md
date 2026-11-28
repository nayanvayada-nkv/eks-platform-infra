# Runbook: test run of Phases 1 to 6 (dev, Mumbai)

Goal: prove the roadmap deliverables, "cluster up, cost noted" (Phase 1), "signed image deployed by
Argo CD" (Phase 2), "unsigned image rejected" (Phase 3), "app serving traffic" (Phase 4), "WAF blocking test
traffic" (Phase 5) and "dashboards + alert test" (Phase 6), then destroy. Expected time 3 to 4 hours, expected cost about **$2**.

**Rule:** nothing is applied without your OK. Steps marked **[You]** are done by you in a browser or
terminal; steps marked **[Claude]** I run after you say go.

## Checks already done (26 Nov 2026, all green)

| Check | Result |
|---|---|
| `terraform fmt` + `validate` on 7 stacks/modules | pass |
| tflint (recursive) | 0 issues |
| Checkov | 211 passed, 0 failed, 18 skipped with written reasons |
| actionlint on both workflows | pass |
| Backend unit tests | 2 passed |
| Image build + run read-only as uid 10001 | pass |
| Trivy (HIGH/CRITICAL, fixable) | 0 findings |
| Cosign v3.1.4 sign + SBOM attest + verify (local registry dry run) | pass |
| Kustomize overlay + app-of-apps chart render | pass |
| AWS CLI identity | account 464243369696, user `eks-platform-project`, ap-south-1 |
| GitHub repo | public, default branch `main` (Argo CD needs no credentials) |

Fixed during the checks: ECR rejected re-signing (Cosign signature tags vs immutable tags), no VPC flow
logs, EKS module defaulted the API to 0.0.0.0/0, one unused variable.

## A. Before the run day ($0)

1. **[You]** Decide to commit and merge to `main`. The pipeline and Argo CD both use `main`; today
   `main` on GitHub only has the initial commit. (I can commit, push the branch and you merge the PR.)
2. **[You]** GitHub > repo Settings > Actions > General > Workflow permissions: tick
   **"Allow GitHub Actions to create and approve pull requests"**. Save.
3. **[You]** Recommended: AWS Console > Billing > Budgets > create a monthly cost budget of **$10** with
   an email alert at 80%. Free, and catches anything left running. (Phase 0 lists budget alerts; not built yet.)
4. **[You]** For Grafana (Phase 6): AWS Console > IAM Identity Center > Enable (free). Create a user
   for yourself, copy its **User ID** into `environments/dev/observability/terraform.tfvars`
   (`grafana_admin_user_ids`). If Managed Grafana is not offered in Mumbai, tell me and we set another region.
5. **[Claude] done:** tfvars and `environments/backend.hcl` are pre-filled (git-ignored). Your IP was
   `103.51.134.100` on 26 Nov; home IPs change, so we re-check it on the run day.

## B. Run day

| # | Who | Step | Time | Check it worked |
|---|---|---|---|---|
| 1 | Claude | Re-check your IP in `environments/dev/eks/terraform.tfvars` | 1 min | matches `curl -s https://checkip.amazonaws.com` |
| 2 | Claude | `bootstrap`: plan, then apply after your OK (state bucket, KMS, GitHub OIDC, plan role) | 3 min | outputs show the bucket name |
| 3 | Claude | Move bootstrap state into S3: rename `backend.tf.off` to `backend.tf`, `terraform init -migrate-state` | 2 min | local state file empty |
| 4 | Claude | `shared/supply-chain`: plan, apply (ECR, Cosign KMS key, build role) | 2 min | outputs `github_build_role_arn` |
| 4b | Claude | `shared/security`: plan, apply (GuardDuty, Security Hub, Config, alerts, $10 budget). Put your email in its `terraform.tfvars` first and confirm the SNS email | 5 min | GuardDuty and Security Hub enabled in the console |
| 5 | **You** | GitHub > Settings > Secrets and variables > Actions > **Variables**: add `AWS_BUILD_ROLE_ARN` (from step 4) and `AWS_PLAN_ROLE_ARN` (from step 2) | 2 min | both listed |
| 6 | Claude | `dev/network`: plan, apply (VPC, NAT, flow logs) | 3 min | 6 subnets |
| 7 | Claude | `dev/eks`: plan, apply (cluster, nodes, add-ons, IAM) | 15 to 20 min | `kubectl get nodes` shows 2 Ready |
| 7b | Claude | `dev/data`: plan, apply (Aurora Serverless v2, Valkey serverless, data KMS key, Pod Identity roles) | 10 to 15 min | outputs show `backend_config` |
| 7c | Claude | `dev/edge`: plan, apply (internal ALB, CloudFront VPC origin + distribution, WAF) | 15 to 20 min | output `url` |
| 7d | Claude | `dev/observability`: plan, apply (AMP workspace + rules + Alertmanager, Managed Grafana, log group, collector roles) | 10 min | outputs `grafana_url` |
| 8 | Claude | `dev/platform`: plan, apply (LB controller, metrics-server, Karpenter, Argo CD, root app). Argo CD then installs Kyverno, Istio ambient and the zero-trust policies in waves | 10 to 15 min | `kubectl -n argocd get applications`: kyverno, istio-*, ztunnel, zero-trust Healthy |
| 9 | Both | Trigger the pipeline: merge a change under `apps/backend/` to `main` (or run it from the Actions tab) | 5 min | all steps green, image in ECR |
| 10 | **You** | Merge the pull request "deploy(backend): dev -> ..." that the pipeline opens | 1 min | PR merged |
| 11 | Claude | Watch Argo CD sync; `cosign verify` the running digest | 3 min | backend pods Running with `@sha256:` image |
| 12 | Claude | Karpenter test: scale backend to 10 replicas | 3 min | a new spot node appears, then goes after scale-down |
| 12b | Claude | Phase 3 demos (section below) | 15 min | each denial message matches |
| 12c | Claude | Phase 4 check (section below) | 10 min | items saved in Aurora, second read from Valkey |
| 12d | Claude | Phase 5 WAF demos (section below) | 10 min | 403 for each attack, 200 for normal traffic |
| 12e | Both | Phase 6: dashboards + alert test (section below) | 20 min | dashboards show traffic; BackendDown email arrives |
| 13 | You | Screenshots (list below) | 15 min | |
| 14 | Claude | Destroy, after your OK (order below) | 15 to 20 min | `terraform state list` empty per stack |

Before step 9 succeeds, the backend app in Argo CD shows **sync failed**: Kyverno refuses the placeholder
image (wrong registry, unsigned). That is expected, and is already a first Phase 3 proof.

## Phase 3 demos (step 12b)

`REG` = `<account>.dkr.ecr.ap-south-1.amazonaws.com/eks-platform`. Each command must be **refused**.

1. **Unsigned image rejected** (the roadmap proof). Push an image that did not go through the pipeline,
   then try to run it by digest:
   ```bash
   aws ecr get-login-password | docker login --username AWS --password-stdin "${REG%%/*}"
   docker build -t "$REG/backend:unsigned-demo" apps/backend && docker push "$REG/backend:unsigned-demo"
   kubectl -n backend run unsigned --image="$REG/backend@<digest printed by push>"
   ```
   Expected: `image is not signed with the project Cosign key`.
2. **Foreign registry rejected:** `kubectl -n backend run nginx --image=nginx:1.29` -> `images must come from ...`.
3. **Tag instead of digest rejected:** `kubectl -n backend run t --image="$REG/backend:unsigned-demo"` -> `pinned by digest`.
4. **Unguarded namespace rejected:** `kubectl create namespace scratch` -> `needs label pod-security...`.
5. **Network blocked:** set the signed backend digest in
   [phase3-demo-client.yaml](phase3-demo-client.yaml), `kubectl apply -f` it, then
   `kubectl -n demo logs client`: the call to the backend times out (default-deny NetworkPolicy plus the
   AuthorizationPolicy, which only allows the ingress gateway and the backend itself).
6. **mTLS on:** `kubectl -n istio-system logs ds/ztunnel | grep backend` shows HBONE connections with
   SPIFFE identities (`spiffe://cluster.local/ns/backend/sa/backend`).

Clean up: `kubectl delete -f docs/runbooks/phase3-demo-client.yaml`.

## Phase 4 check (step 12c)

```bash
URL=$(cd environments/dev/edge && terraform output -raw url)   # https://<id>.cloudfront.net
curl -s "$URL/items" -X POST -H 'content-type: application/json' -d '{"name":"first"}'
curl -s "$URL/items"   # "source": "database"
curl -s "$URL/items"   # "source": "cache" (Valkey, 30 s)
kubectl -n backend logs job/db-migrate   # "role app uses IAM authentication"
```

The first request after Aurora was idle takes ~15 s (resume from 0 ACU). If pods stay not-ready,
check `kubectl -n backend logs deploy/backend` for the IAM token or TLS error.

## Phase 5 WAF demos (step 12d)

Each attack must return **403** from CloudFront/WAF; normal requests return 200.

```bash
curl -s -o /dev/null -w "%{http_code}\n" "$URL/items"                                   # 200
curl -s -o /dev/null -w "%{http_code}\n" "$URL/items?q=<script>alert(1)</script>"       # 403 (XSS, Common Rule Set)
curl -s -o /dev/null -w "%{http_code}\n" "$URL/items?id=1%27%20OR%20%271%27=%271"       # 403 (SQL injection)
curl -s -o /dev/null -w "%{http_code}\n" -H 'User-Agent: ${jndi:ldap://x/a}' "$URL/"   # 403 (Log4j, Known Bad Inputs)
for i in $(seq 1 150); do curl -s -o /dev/null -w "%{http_code} " "$URL/"; done; echo   # 200s, then 403s (rate limit)
```

Then: WAF console (us-east-1) > Web ACLs > `eks-platform-dev-edge` > sampled requests, and the log group
`aws-waf-logs-eks-platform-dev-edge`. The ALB has no public DNS name that answers: that is the point.

## Phase 6 dashboards + alert test (step 12e)

1. `scripts/grafana-dashboards.sh` loads `Backend SLO` and `Platform` from Git.
2. Grafana > Apps > AWS Data Sources > add the Amazon Managed Prometheus workspace (ap-south-1), then pick
   it in each dashboard's "Data source" box. Also add X-Ray and CloudWatch the same way.
3. Generate traffic: `for i in $(seq 1 300); do curl -s -o /dev/null "$URL/items"; sleep 0.2; done`.
   Backend SLO shows requests, latency, availability; X-Ray shows traces with Aurora/Valkey spans;
   CloudWatch Logs group `/eks/eks-platform-dev/containers` has the gunicorn access lines.
4. **Alert test:** `kubectl -n backend scale deploy backend --replicas=0` (Argo CD self-heal will put it
   back, so first pause it: `kubectl -n argocd patch application backend-dev --type merge -p
   '{"spec":{"syncPolicy":{"automated":null}}}'`). Within ~5 minutes an email "[FIRING] BackendDown"
   arrives; scale back to 2 (or re-enable auto-sync) and a "[RESOLVED]" email follows.

## Screenshots for your portfolio

1. `kubectl get nodes -o wide` (system + Karpenter spot node).
2. GitHub Actions run: Trivy step, Cosign step, summary with the digest.
3. The auto-created GitOps pull request.
4. Argo CD UI: root-dev and backend-dev Healthy/Synced (`kubectl -n argocd port-forward svc/argocd-server 8080:443`).
5. Terminal: `cosign verify --key awskms:///alias/eks-platform-cosign <image@digest>` success.
6. ECR console: image with `.sig` and `.att` tags and scan result.
7. AWS Cost Explorer for the day.
8. Phase 3: the `kubectl` denial for the unsigned image, and `kubectl -n argocd get applications` all Healthy.
9. Phase 5: the 403s in the terminal, WAF sampled requests, GuardDuty and Security Hub summary pages.
10. Phase 6: Backend SLO dashboard, an X-Ray trace map, the BackendDown alert email.

## Destroy order

1. `kubectl -n argocd delete application root-dev` (removes the backend app and its pods cleanly).
2. `dev/platform` destroy, then `dev/observability`, then `dev/edge` (CloudFront takes ~15 min to disable and delete), then `dev/data`,
   `dev/eks`, `dev/network` (`scripts/destroy-dev.sh` does this order).
3. Keep `bootstrap` (never destroyed, see CLAUDE.md) and normally `shared/supply-chain` too
   (about $2/month for two KMS keys plus cents of S3).
4. `shared/security` (GuardDuty, Security Hub, Config) bills a few dollars a month while on. Destroy it
   after the run only if you say so; the budget alert is free and worth keeping.

## If something fails

Stop, copy the error, and we fix it before continuing. A failed apply leaves partial resources: either
re-apply after the fix or destroy that stack before ending the day. Never leave the eks or network
stack running overnight by accident (about $6/day).
