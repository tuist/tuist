# AWS Marketplace one-click deployment

This directory contains the AWS-specific packaging path for buyer-owned Tuist deployments. It intentionally sits outside `infra/helm/tuist` so the main chart stays provider-agnostic.

## Product shape

The first deployable milestone is an **existing EKS** Marketplace-style stack:

1. The buyer selects an existing EKS cluster.
2. CloudFormation creates AWS dependencies:
   - RDS Postgres for Tuist relational data.
   - S3 buckets for Tuist artifacts, cache artifacts, Xcode cache artifacts, and registry artifacts.
   - An IAM role for the Tuist server ServiceAccount to access those buckets through IRSA.
3. CloudFormation installs the Tuist Helm chart into the cluster through the `AWSQS::Kubernetes::Helm` public extension.

This is not the final Marketplace Quick Launch experience yet. It is the smallest end-to-end path that exercises the AWS procurement/deployment shape without also provisioning the EKS cluster.

## Files

- `cloudformation/tuist-existing-eks.yaml` - CloudFormation entrypoint for an existing EKS cluster.
- `helm/values-existing-eks.yaml` - Helm values overlay that mirrors the same deployment shape for local chart rendering.

## Existing-EKS prerequisites

The first template assumes the buyer already has:

- An EKS cluster with Linux worker nodes and a default `ReadWriteOnce` storage class for embedded ClickHouse.
- The `AWSQS::Kubernetes::Helm` and `AWSQS::Kubernetes::Resource` public CloudFormation extensions activated in the target account and Region.
- An EKS IAM OIDC provider configured for IRSA.
- The EKS worker node security group ID, so the template can allow Postgres traffic from the cluster.
- A public Tuist URL. The current template exposes the server through a `LoadBalancer` Service; DNS/TLS automation is deferred to the full Quick Launch milestone.
- A valid Tuist Enterprise self-hosting license key.

## Marketplace readiness gaps

Before submitting this as a public AWS Marketplace container product:

- Mirror every required image into AWS Marketplace-managed ECR repositories, including supporting images such as ClickHouse.
- Replace the public GHCR chart source with the Marketplace-managed Helm artifact.
- Verify whether the Marketplace review path supports the `AWSQS::Kubernetes::Helm` extension directly, or whether AWS requires a different Quick Launch wrapper.
- Add the full empty-account Quick Launch template that provisions VPC, EKS, node groups, ingress, and DNS.
- Decide whether the first public listing is BYOL or uses AWS Marketplace container billing/licensing.
- Produce the required architecture diagram and buyer usage instructions.

## Validation

CI validates this directory through `.github/workflows/aws-marketplace.yml` when Marketplace assets or the Tuist Helm chart change.

The required offline job checks:

- CloudFormation YAML parsing with `yq`.
- CloudFormation linting with `cfn-lint`.
- Helm linting with `values-existing-eks.yaml`.
- Helm rendering plus Kubernetes schema validation with `kubeconform`.

The workflow also has an optional AWS validation job. It runs `aws cloudformation validate-template` only when the repository variable `AWS_MARKETPLACE_VALIDATE_ROLE_ARN` is set to an IAM role that GitHub Actions can assume through OIDC.

Render the current Helm overlay from the repository root:

```bash
helm template tuist infra/helm/tuist \
  -f infra/aws-marketplace/helm/values-existing-eks.yaml
```

When AWS credentials are available, validate the CloudFormation template:

```bash
aws cloudformation validate-template \
  --template-body file://infra/aws-marketplace/cloudformation/tuist-existing-eks.yaml
```

The CloudFormation stack depends on the `AWSQS::Kubernetes::Helm` and `AWSQS::Kubernetes::Resource` public extensions being activated in the buyer account and Region.
