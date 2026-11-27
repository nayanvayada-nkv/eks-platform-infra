# ADR 0009: Observability with AWS-managed backends (AMP, Managed Grafana, CloudWatch, X-Ray)

- Status: accepted (code written 27 Nov 2026, not applied)
- Context: Phase 6 (Prometheus, Grafana, logs, tracing, alerts, SLOs). Proof: "dashboards + alert test".
  Constraints: no Docker Hub images (Grafana's image is only there), small dev cluster, cost-sensitive.
- Decisions:
  1. **Metrics:** in-cluster Prometheus (kube-prometheus-stack, quay.io/registry.k8s.io images) scrapes
     and keeps 6 h, then **remote-writes to Amazon Managed Service for Prometheus** with SigV4 (Pod
     Identity, `aps:RemoteWrite` on one workspace). AMP stores, evaluates rules and runs Alertmanager,
     so alerting survives the cluster. A keep-list on remote write ships only the metrics dashboards,
     SLOs and alerts use (AMP bills per sample).
  2. **Dashboards: Amazon Managed Grafana** (you chose it over building our own image or CloudWatch
     only). Login through IAM Identity Center, UI limited to your IP by a prefix list, workspace role is
     read-only. Dashboards are JSON in Git, loaded by `scripts/grafana-dashboards.sh` with a 1-day token.
  3. **SLOs:** availability 99.5% (non-5xx) and p95 < 500 ms. Multi-window, multi-burn-rate alerts
     (14.4x over 1 h + 5 m pages; 6x over 6 h + 30 m warns). Rules are unit-tested with `promtool`.
  4. **Alerts** go to the shared/security SNS topic (one email for security, cost and reliability).
     Alert test: scale the backend to 0 -> `BackendDown` email within ~5 minutes.
  5. **Logs:** AWS for Fluent Bit (public.ecr.aws) -> one KMS-encrypted CloudWatch log group, 14 days.
  6. **Traces:** OpenTelemetry SDK in the app (Flask, psycopg, redis) -> ADOT collector -> AWS X-Ray.
     25% head sampling. Only the collector holds X-Ray permissions.
  7. **Metrics stay private and authenticated:** the app serves `/metrics` on port 9464, which is not in
     the Service or the gateway route. The monitoring namespace joins the ambient mesh, and only the
     `prometheus` identity may call 9464 (AuthorizationPolicy); NetworkPolicy allows the HBONE port.
- Consequences: AMP ingestion + storage (cents per hour with the keep-list), Managed Grafana ~$9 for a
  month in which an editor logs in, CloudWatch Logs ingestion, X-Ray (first 100k traces/month free).
  Needs IAM Identity Center enabled once (console) before Grafana logins work. Istio L7 metrics/traces
  need a waypoint proxy (not deployed); ztunnel provides L4 metrics only.
