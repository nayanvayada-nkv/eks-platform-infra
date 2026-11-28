# ADR 0001: Temporary admin IAM user for bootstrap

- Status: accepted (temporary)
- Context: Phase 0 needs broad permissions to create the state backend and OIDC role.
- Decision: use an IAM user with MFA and AdministratorAccess, only from a local machine, never in CI.
- Consequences: a standing admin identity exists. Exit plan: move to IAM Identity Center
  (short-lived credentials), create a scoped Terraform apply role, remove the admin policy
  and delete access keys by the end of Phase 3.
