# AWS Marketplace

This node covers AWS Marketplace packaging for buyer-owned Tuist deployments.

## Scope
- CloudFormation templates that support Marketplace-style one-click deployment
- AWS-specific Helm values overlays for EKS installs
- Marketplace readiness notes for images, IAM, networking, and buyer instructions

## Conventions
- Keep the main `infra/helm/tuist` chart provider-agnostic. Put AWS defaults and Marketplace review constraints here.
- Prefer AWS-managed infrastructure for first-click buyer deployments: RDS for Postgres, S3 for object storage, and EKS for Kubernetes workloads.
- Use workload identity for AWS access. Do not introduce long-lived AWS access keys in templates or values.
- Treat Marketplace submission constraints as product constraints: document them next to the template that must satisfy them.
- Validate CloudFormation templates with YAML parsing first, then `aws cloudformation validate-template` when AWS credentials are available.

## Related Context
- Parent infra context: `infra/AGENTS.md`
- Tuist Helm chart: `infra/helm/tuist/AGENTS.md`
- Server self-hosting docs: `server/priv/docs/en/guides/server/self-host/control-plane.md`
