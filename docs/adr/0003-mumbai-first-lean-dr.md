# ADR 0003: Mumbai first, lean DR later

- Status: accepted
- Context: multi-region DR is standard, expensive, and not the differentiator of this project.
- Decision: build and prove everything in Mumbai (dev) first. Add one warm-standby DR region in
  Phase 7, scaled down (pilot light), and measure RTO / RPO with a real failover test.
- Consequences: lower cost, faster learning. A third region is optional and justified only by
  data-residency or user-distribution needs.
