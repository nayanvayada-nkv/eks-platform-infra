# ADR 0002: Single AWS account, environments separated by folders and naming

- Status: accepted
- Context: cost and simplicity for a build-out project.
- Decision: one AWS account; `environments/<env>/<stack>` folders (originally `live/`), separate state per stack,
  environment in resource names and tags.
- Consequences: weaker blast-radius isolation than multi-account. Revisit with AWS Organizations
  (separate prod, non-prod, security and shared-services accounts) if the project grows.
