"""All diagrams used by the guides (registered by name)."""

from diagrams import boxes, diagram, flow, layers


@diagram
def arch_overall():
    I = {
        "user": (10, 30, 120, 52, "Shoppers / agents", "browser or app", "grey"),
        "cf": (160, 30, 140, 52, "CloudFront + WAF", "HTTPS, blocks attacks", "amber"),
        "alb": (330, 30, 130, 52, "Internal ALB", "no public address", "amber"),
        "gw": (490, 30, 130, 52, "Istio gateway", "entry to the mesh", "blue"),
        "api": (490, 140, 130, 60, "Backend API pods", "EKS, mTLS, signed image", "green"),
        "db": (250, 260, 130, 56, "Aurora PostgreSQL", "data + pgvector", "navy"),
        "cache": (400, 260, 120, 56, "Valkey cache", "fast reads", "navy"),
        "ai": (540, 260, 130, 56, "Amazon Bedrock", "Titan + Claude", "purple"),
        "gh": (10, 150, 130, 56, "GitHub Actions", "test, scan, sign", "grey"),
        "ecr": (10, 260, 130, 56, "Amazon ECR", "signed images", "grey"),
        "argo": (250, 150, 140, 56, "Argo CD", "syncs Git to cluster", "blue"),
        "obs": (650, 140, 100, 60, "AMP, Grafana, X-Ray", "metrics, traces", "green"),
        "dr": (10, 350, 740, 48, "Frankfurt DR (pilot light)", "Aurora Global DB copy, ECR + key replicas, same Terraform code", "red"),
    }
    A = [("user", "cf"), ("cf", "alb"), ("alb", "gw"), ("gw", "api"), ("api", "db"), ("api", "cache"), ("api", "ai"),
         ("gh", "ecr", "push"), ("argo", "api", "deploy"), ("api", "obs")]
    return boxes(I, A, h=408, groups=[(230, 120, 410, 210, "Amazon EKS, Mumbai (ap-south-1)", "green")]), \
        "The whole platform: how a request travels (top row), how code is delivered (left) and where DR lives (bottom)."


@diagram
def arch_layers():
    return layers([
        ("Edge", "CloudFront HTTPS, WAF (OWASP, Log4j, SQLi, rate limit), Shield Standard, internal-only ALB", "amber"),
        ("Network", "Private subnets, one NAT, VPC endpoints (S3, Secrets Manager, Bedrock), flow logs, API restricted to one IP", "blue"),
        ("Identity", "GitHub OIDC for CI, EKS access entries, Pod Identity per workload, IMDSv2 hop limit 1", "purple"),
        ("Supply chain", "Trivy gate, SBOM, Cosign signature with a KMS key, deploy by digest via pull request", "navy"),
        ("Cluster", "Kyverno admission policies, Istio ambient mTLS + AuthZ, default-deny NetworkPolicy, PSA restricted", "green"),
        ("Data", "KMS everywhere, IAM-token logins (no passwords), row-level security per tenant", "red"),
        ("Detect + respond", "GuardDuty, Security Hub, Config, SLO alerts, budget alerts, game days", "grey"),
    ]), "Zero Trust in layers: an attacker has to beat every layer, not just one."


@diagram
def flow_request():
    return flow([
        ("Shopper opens the app", "HTTPS request", "grey"), ("CloudFront", "nearest edge location", "amber"),
        ("WAF", "drop attacks, rate limit", "amber"), ("Internal ALB", "via VPC origin", "amber"),
        ("Istio gateway", "mTLS from here on", "blue"), ("NetworkPolicy + AuthZ", "is this caller allowed?", "green"),
        ("Backend pod", "Flask API", "green"), ("Aurora / Valkey / Bedrock", "IAM token, no password", "navy"),
    ]), "One request from a phone to the database and back, and the check at each hop."


@diagram
def flow_deploy():
    return flow([
        ("Developer merges code", "apps/backend", "grey"), ("Tests", "pytest", "grey"),
        ("Build image", "ECR Public base", "blue"), ("Trivy scan", "fail on fixable HIGH", "red"),
        ("SBOM", "list of every package", "blue"), ("Push by digest", "ECR, immutable", "blue"),
        ("Cosign sign", "key stays in KMS", "purple"), ("GitOps PR", "new digest in Git", "amber"),
        ("Human merges PR", "= deploy approval", "amber"), ("Argo CD syncs", "pull, not push", "green"),
        ("Kyverno checks", "signed? our ECR? digest?", "green"), ("Pods running", "rollback = git revert", "green"),
    ]), "From a code change to running pods. CI never touches the cluster; Git is the only way in."


@diagram
def flow_stacks():
    return flow([
        ("bootstrap", "state bucket, OIDC", "grey"), ("shared/supply-chain", "ECR, Cosign key", "navy"),
        ("shared/security", "GuardDuty, budget", "red"), ("dev/network", "VPC, NAT, endpoints", "blue"),
        ("dev/eks", "cluster, nodes, IAM", "green"), ("dev/data", "Aurora, Valkey", "navy"),
        ("dev/edge", "CloudFront, WAF, ALB", "amber"), ("dev/observability", "AMP, Grafana", "green"),
        ("dev/platform", "Karpenter, Argo CD", "purple"),
    ], cols=3), "Terraform stacks in apply order. Each has its own state file; destroy runs in reverse."


@diagram
def supply_chain_trust():
    I = {
        "ci": (20, 30, 150, 60, "GitHub Actions", "main branch only", "grey"),
        "oidc": (20, 140, 150, 60, "GitHub OIDC token", "no stored AWS keys", "purple"),
        "role": (230, 140, 150, 60, "IAM build role", "push + kms:Sign", "purple"),
        "kms": (440, 140, 140, 60, "KMS Cosign key", "private key never leaves", "purple"),
        "ecr": (230, 30, 150, 60, "ECR repo", "image + .sig + .att", "blue"),
        "kyv": (440, 30, 140, 60, "Kyverno", "verifies at admission", "green"),
        "pub": (620, 140, 120, 60, "Public key", "kms:GetPublicKey", "green"),
    }
    A = [("ci", "oidc"), ("oidc", "role", "assume"), ("role", "kms", "sign"), ("role", "ecr", "push"), ("ecr", "kyv", "pull sig"),
         ("kms", "pub"), ("pub", "kyv")]
    return boxes(I, A, h=220), "Who can sign and who can verify: only CI on main can sign; the cluster can only verify."


@diagram
def admission():
    return flow([
        ("kubectl / Argo CD", "create Pod", "grey"), ("API server", "authn + RBAC", "blue"),
        ("Pod Security", "restricted profile", "green"), ("Kyverno webhook", "CEL policies", "green"),
        ("Registry + digest?", "our ECR only", "amber"), ("Signed + SBOM?", "Cosign, KMS key", "purple"),
        ("Allowed", "pod scheduled", "green"), ("Denied", "clear error message", "red"),
    ]), "Admission: every new pod passes Pod Security and Kyverno before it can run (fail closed)."


@diagram
def mesh():
    I = {
        "gw": (20, 40, 150, 60, "Istio gateway", "sa: istio-ingress", "blue"),
        "zt1": (230, 40, 130, 60, "ztunnel (node A)", "HBONE mTLS", "navy"),
        "zt2": (420, 40, 130, 60, "ztunnel (node B)", "checks AuthZ", "navy"),
        "be": (610, 40, 130, 60, "backend pod", "sa: backend", "green"),
        "other": (230, 160, 150, 60, "pod in another namespace", "no permission", "red"),
        "np": (420, 160, 130, 60, "NetworkPolicy", "default deny", "red"),
    }
    A = [("gw", "zt1"), ("zt1", "zt2", "mTLS 15008"), ("zt2", "be"), ("other", "np", "blocked")]
    return boxes(I, A, h=240), "Istio ambient: ztunnel on every node encrypts pod-to-pod traffic and checks identities; NetworkPolicy blocks by address."


@diagram
def data_access():
    I = {
        "pod": (20, 40, 140, 60, "Backend pod", "service account backend", "green"),
        "agent": (220, 40, 160, 60, "Pod Identity agent", "gives temporary AWS creds", "purple"),
        "sign": (440, 40, 140, 60, "Sign a token", "15 minutes, local", "purple"),
        "db": (220, 160, 160, 60, "Aurora (TLS verify-full)", "user app: SELECT, INSERT", "navy"),
        "vk": (440, 160, 140, 60, "Valkey (TLS)", "keys backend:* only", "navy"),
        "mig": (20, 160, 140, 60, "db-migrate Job", "reads admin secret", "amber"),
        "sm": (620, 100, 120, 60, "Secrets Manager", "admin password", "amber"),
    }
    A = [("pod", "agent"), ("agent", "sign"), ("sign", "db", "IAM token"), ("sign", "vk", "IAM token"), ("mig", "db", "admin, once"), ("mig", "sm")]
    return boxes(I, A, h=240), "No passwords in the app: it signs short-lived IAM tokens; only the migrate Job reads the admin secret."


@diagram
def edge():
    I = {
        "u": (20, 50, 120, 56, "Shopper", "your IP in dev", "grey"),
        "cf": (180, 50, 130, 56, "CloudFront", "HTTPS, headers", "amber"),
        "waf": (180, 150, 130, 56, "WAF (us-east-1)", "rules + rate limit", "red"),
        "vo": (350, 50, 130, 56, "VPC origin", "CloudFront ENIs", "amber"),
        "alb": (520, 50, 110, 56, "Internal ALB", "private subnets", "blue"),
        "gw": (520, 150, 110, 56, "Istio gateway pods", "TargetGroupBinding", "green"),
        "x": (660, 50, 90, 56, "Internet", "cannot reach ALB", "red"),
    }
    A = [("u", "cf"), ("cf", "waf", "inspect"), ("cf", "vo"), ("vo", "alb"), ("alb", "gw")]
    return boxes(I, A, h=230), "The only way in: CloudFront + WAF, then a private hop to an ALB that has no public address."


@diagram
def observability():
    I = {
        "app": (20, 30, 130, 56, "Backend", "/metrics, OTel", "green"),
        "prom": (200, 30, 140, 56, "Prometheus (6 h)", "scrape + filter", "blue"),
        "amp": (390, 30, 150, 56, "Managed Prometheus", "rules + Alertmanager", "navy"),
        "graf": (590, 30, 150, 56, "Managed Grafana", "dashboards", "purple"),
        "fb": (200, 120, 140, 56, "Fluent Bit", "container logs", "blue"),
        "cw": (390, 120, 150, 56, "CloudWatch Logs", "KMS, 14 days", "navy"),
        "otel": (200, 210, 140, 56, "ADOT collector", "traces", "blue"),
        "xray": (390, 210, 150, 56, "AWS X-Ray", "trace map", "navy"),
        "sns": (590, 120, 150, 56, "SNS -> email", "SLO + security alerts", "red"),
    }
    A = [("app", "prom", "metrics"), ("prom", "amp", "remote write"), ("amp", "graf"), ("amp", "sns", "alerts"),
         ("fb", "cw"), ("otel", "xray"), ("app", "otel", "spans")]
    return boxes(I, A, h=280), "Metrics, logs and traces each flow to a managed AWS service; alerts reach your email even if the cluster is down."


@diagram
def slo_burn():
    return flow([
        ("SLO 99.5%", "0.5% may fail per 30 days", "green"), ("Error budget", "~3.6 hours a month", "green"),
        ("Burn 14x for 1 h", "and still burning (5 m)", "red"), ("Page now", "critical email", "red"),
        ("Burn 6x for 6 h", "and still burning (30 m)", "amber"), ("Warn", "fix this week", "amber"),
    ], cols=3), "Burn-rate alerting: alert on how fast the budget is spent, not on every single error."


@diagram
def dr():
    I = {
        "mw": (20, 40, 160, 60, "Aurora writer", "Mumbai", "green"),
        "fr": (480, 40, 170, 60, "Aurora secondary", "Frankfurt, headless", "amber"),
        "ecr1": (20, 140, 160, 56, "ECR Mumbai", "image + signature", "blue"),
        "ecr2": (480, 140, 170, 56, "ECR Frankfurt", "replica", "blue"),
        "k1": (20, 230, 160, 56, "KMS keys", "multi-Region", "purple"),
        "k2": (480, 230, 170, 56, "KMS replicas", "same key material", "purple"),
        "tf": (250, 320, 230, 56, "Same Terraform code", "dr workspace builds EKS on demand", "grey"),
    }
    A = [("mw", "fr", "storage replication (< 1 s)"), ("ecr1", "ecr2", "replication"), ("k1", "k2", "replica keys")]
    return boxes(I, A, h=390), "Pilot light: data, images and keys are always copied to Frankfurt; compute is built from the same code when needed."


@diagram
def drill():
    return flow([
        ("Write marker", "via Mumbai API", "grey"), ("Switchover", "aws rds switchover", "amber"),
        ("Wait", "Frankfurt is writer", "amber"), ("RTO (db)", "seconds measured", "green"),
        ("Argo retry", "migrate job succeeds", "blue"), ("First write OK", "RTO (app)", "green"),
        ("Marker present?", "RPO = 0", "green"), ("Switch back", "home", "grey"),
    ]), "The DR drill script: measured numbers instead of a diagram-only promise."


@diagram
def rag():
    return flow([
        ("Agent asks", "API key = tenant", "grey"), ("Embed question", "Titan, 1024 numbers", "purple"),
        ("pgvector search", "this tenant only (RLS)", "navy"), ("Top 5 chunks", "nearest meaning", "navy"),
        ("Claude on Bedrock", "answer only from chunks", "purple"), ("Answer + sources", "citations, cached 10 min", "green"),
    ], cols=3), "Retrieval-augmented generation: find the right paragraphs first, then let the model answer only from them."


@diagram
def tenancy():
    I = {
        "a": (20, 40, 150, 56, "Tenant A key", "tk_...", "green"),
        "b": (20, 140, 150, 56, "Tenant B key", "tk_...", "blue"),
        "api": (230, 90, 140, 56, "API", "sets app.tenant_id", "grey"),
        "rls": (430, 90, 150, 56, "Row-level security", "FORCE'd policy", "red"),
        "da": (630, 40, 120, 56, "A's documents", "visible to A", "green"),
        "db": (630, 140, 120, 56, "B's documents", "visible to B", "blue"),
    }
    A = [("a", "api"), ("b", "api"), ("api", "rls"), ("rls", "da"), ("rls", "db")]
    return boxes(I, A, h=220), "Tenant isolation is enforced by PostgreSQL itself, so an app bug cannot show one customer another's data."


@diagram
def loadtest():
    return flow([
        ("Smoke", "5 users, 1 min", "green"), ("Ramp", "to 200 users", "blue"), ("Spike", "jump to 300", "amber"),
        ("Soak", "60 users, 30 min", "purple"), ("Watch", "HPA, Karpenter, ACU, SLO", "grey"), ("Report", "limits + fixes", "green"),
    ], cols=3), "Load test profiles: each answers a different question about scale."


@diagram
def fde():
    return flow([
        ("Vague ask", "'we want a chatbot'", "grey"), ("Discovery", "stakeholders, workflow", "blue"),
        ("Measurable goal", "5 min -> 30 s", "green"), ("Design", "map to platform", "navy"),
        ("Onboard", "key + PR + docs", "purple"), ("Eval", "90% go-live bar", "amber"),
        ("Demo + pilot", "8 agents, 4 weeks", "green"), ("Handover", "SLOs, RACI, limits", "grey"),
    ]), "A Forward Deployed Engineer engagement from first call to handover."


@diagram
def quickcart():
    I = {
        "app": (20, 40, 150, 56, "QuickCart app", "shop + food orders", "grey"),
        "cat": (230, 10, 150, 50, "Catalog + cart", "Phase 4: items API", "green"),
        "sup": (230, 80, 150, 50, "Support assistant", "Phase 9: RAG", "purple"),
        "pay": (230, 150, 150, 50, "Sale-day traffic", "Phase 8: load test", "amber"),
        "plat": (450, 60, 290, 76, "This platform", "secure delivery, scaling, monitoring, DR", "navy"),
    }
    A = [("app", "cat"), ("app", "sup"), ("app", "pay"), ("cat", "plat"), ("sup", "plat"), ("pay", "plat")]
    return boxes(I, A, h=210), "QuickCart: the fictional shopping + food delivery app used as the running example in every guide."


@diagram
def arch_full():
    I = {
        # outside AWS (left column)
        "dev": (20, 20, 250, 56, "Developer", "pull request to GitHub", "grey"),
        "repo": (20, 120, 250, 64, "GitHub repo (main)", "Terraform, gitops/, apps/", "grey"),
        "gha": (20, 230, 250, 70, "GitHub Actions", "test, Trivy, SBOM, Cosign sign, GitOps PR", "grey"),
        "oidc": (20, 350, 250, 60, "GitHub OIDC", "no stored AWS keys", "purple"),
        "tfstate": (20, 460, 250, 70, "Terraform state", "S3 bucket + KMS, never destroyed", "grey"),
        # edge (global)
        "users": (560, 20, 190, 56, "Shoppers / support agents", "browser, phone", "grey"),
        "r53": (800, 20, 170, 56, "Route 53 + ACM", "optional custom domain", "amber"),
        "cf": (1010, 20, 210, 56, "CloudFront", "HTTPS, security headers", "amber"),
        "waf": (1270, 20, 230, 56, "AWS WAF (us-east-1)", "OWASP, Log4j, SQLi, rate limit", "red"),
        # Mumbai regional services
        "ecr": (330, 165, 140, 64, "Amazon ECR", "signed images by digest", "blue"),
        "kms": (475, 165, 140, 64, "AWS KMS", "Cosign, data, EKS keys", "purple"),
        "sm": (620, 165, 140, 64, "Secrets Manager", "DB admin secret", "purple"),
        "bedrock": (765, 165, 140, 64, "Amazon Bedrock", "Titan + Claude", "purple"),
        "amp": (910, 165, 140, 64, "Managed Prometheus", "rules + Alertmanager", "green"),
        "grafana": (1055, 165, 140, 64, "Managed Grafana", "Identity Center login", "green"),
        "cwx": (475, 245, 140, 56, "CloudWatch + X-Ray", "logs, traces", "green"),
        "sns": (1055, 245, 140, 56, "SNS -> email", "SLO + security alerts", "red"),
        # VPC
        "nat": (345, 375, 150, 56, "NAT gateway", "public subnet", "amber"),
        "vo": (345, 450, 150, 64, "CloudFront VPC origin", "ENIs in private subnets", "amber"),
        "alb": (345, 545, 150, 64, "Internal ALB", "no public address", "amber"),
        "vpce": (345, 645, 150, 110, "VPC endpoints", "S3, Secrets Manager, bedrock-runtime, bedrock-mantle", "blue"),
        # EKS (three columns with gaps at x 705-725 and 890-910 for arrows)
        "gw": (540, 395, 165, 64, "Istio ingress gateway", "ns istio-ingress", "blue"),
        "be": (725, 395, 165, 64, "Backend API pods", "ns backend, HPA, mTLS", "green"),
        "mig": (910, 395, 160, 64, "db-migrate Job", "Argo CD sync hook", "green"),
        "kyv": (540, 485, 165, 64, "Kyverno", "signed images only", "red"),
        "istio": (725, 485, 165, 64, "istiod + ztunnel + CNI", "ambient mTLS", "blue"),
        "argo": (910, 485, 160, 64, "Argo CD", "app of apps, waves", "purple"),
        "prom": (540, 575, 165, 64, "Prometheus + ADOT", "ns monitoring", "green"),
        "fb": (725, 575, 165, 64, "Fluent Bit", "ns logging", "green"),
        "ks": (910, 575, 160, 64, "Karpenter, LB ctrl", "CoreDNS (kube-system)", "navy"),
        "sys": (540, 665, 165, 56, "System nodes", "2x t3.medium, IMDSv2 hop 1", "grey"),
        "spot": (725, 665, 165, 56, "Karpenter nodes", "spot first, 16 vCPU cap", "grey"),
        "addons": (910, 665, 160, 56, "EKS add-ons", "VPC CNI, Pod Identity, EBS", "grey"),
        # data
        "aurora": (540, 765, 340, 64, "Aurora PostgreSQL Serverless v2", "IAM login, pgvector, row-level security, KMS", "navy"),
        "valkey": (895, 765, 175, 64, "Valkey Serverless", "IAM login, TLS, KMS", "navy"),
        # DR
        "dr_aur": (1240, 400, 330, 64, "Aurora secondary (headless)", "Global Database, < 1 s lag", "red"),
        "dr_ecr": (1240, 480, 330, 56, "ECR replica", "images + Cosign signatures", "red"),
        "dr_kms": (1240, 550, 330, 56, "KMS replica keys + secret replica", "verify and decrypt without Mumbai", "red"),
        "dr_eks": (1240, 620, 330, 64, "EKS + platform built on demand", "same Terraform, dr workspace", "red"),
        # account security
        "gd": (1240, 745, 160, 56, "GuardDuty", "EKS audit logs", "red"),
        "sh": (1410, 745, 160, 56, "Security Hub", "AWS best practices", "red"),
        "cfg": (1240, 815, 160, 56, "AWS Config", "daily recording", "grey"),
        "bud": (1410, 815, 160, 56, "Budget $10", "email at 80%", "grey"),
    }
    A = [
        ("users", "r53"), ("r53", "cf"), ("cf", "waf", "inspect"),
        ("dev", "repo"), ("repo", "gha"), ("gha", "oidc", "assume role"),
        ("vo", "alb"), ("alb", "gw"), ("gw", "be"), ("mig", "argo"),
        ("amp", "grafana"), ("amp", "sns"),
    ]
    G = [
        (305, 130, 910, 770, "AWS Mumbai (ap-south-1): primary", "green"),
        (325, 335, 885, 550, "VPC 10.20.0.0/16 (private subnets in 3 AZs)", "blue"),
        (520, 372, 570, 362, "Amazon EKS 1.36", "navy"),
        (1225, 370, 360, 330, "AWS Frankfurt (eu-central-1): DR pilot light", "red"),
        (1225, 715, 360, 175, "Account security (shared/security)", "red"),
    ]
    svg = boxes(I, A, w=1600, h=910, groups=G)

    def path(d, color, dashed=False, width=2, arrow=True):
        dash = ' stroke-dasharray="6 4"' if dashed else ""
        end = ' marker-end="url(#a)"' if arrow else ""
        return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}"{dash}{end}/>'

    def text(x, y, t, color, rotate=False, anchor="middle"):
        rot = f' transform="rotate(-90 {x} {y})"' if rotate else ""
        return f'<text x="{x}" y="{y}" font-size="10.5" fill="{color}" text-anchor="{anchor}"{rot}>{t}</text>'

    extra = "".join([
        # viewer traffic
        path("M1115,76 V110 H296 V482 H343", "#a35b00"),
        text(700, 104, "viewer traffic: CloudFront -> VPC origin -> internal ALB -> gateway -> pods", "#a35b00"),
        # CI pushes and signs
        path("M270,265 H400 V231", "#2457a6"),
        text(345, 259, "push + sign", "#2457a6"),
        # Argo CD pulls Git
        path("M270,150 H286 V322 H1080 V517 H1072", "#6a3fb0", dashed=True),
        text(820, 346, "Argo CD pulls Git (CI never touches the cluster)", "#6a3fb0"),
        # private AWS APIs through VPC endpoints
        path("M420,645 V632 H318 V309 H690 V231", "#2457a6", dashed=True, width=1.6),
        path("M690,309 H835 V231", "#2457a6", dashed=True, width=1.6),
        text(311, 520, "private AWS APIs via VPC endpoints", "#2457a6", rotate=True),
        # backend to endpoints and data
        path("M725,447 H711 V745 H497", "#2457a6", width=1.6),
        path("M725,430 H718 V763", "#1b2430", width=1.6),
        path("M890,430 H900 V763", "#1b2430", width=1.6),
        text(760, 755, "IAM token", "#1b2430"),
        # metrics to AMP
        path("M540,607 H530 V360 H980 V231", "#1f7a4d", width=1.6),
        text(985, 300, "metrics", "#1f7a4d", anchor="start"),
        # replication to Frankfurt
        path("M455,165 V157 H1216 V508 H1238", "#b3261e", dashed=True, width=1.6),
        text(840, 153, "ECR images + signatures, KMS keys, admin secret replicated to Frankfurt", "#b3261e"),
        path("M710,829 V862 H1221 V432 H1238", "#b3261e", dashed=True, width=1.8),
        text(960, 857, "Aurora Global Database replication", "#b3261e"),
    ])
    svg = svg.replace("</svg>", extra + "</svg>")
    return svg, ("Full architecture as built in code: global edge (top), Mumbai primary (centre), CI/CD and state "
                 "(left), Frankfurt DR and account security (right). Solid = traffic or calls, dashed = replication, GitOps pull, private APIs.")
