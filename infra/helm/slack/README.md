# Slack Invitation App Helm Chart

Standalone chart for deploying the public Slack invitation app at
`slack.tuist.dev`.

## What it deploys

- One Phoenix `Deployment`
- One `Service`
- Optional public `Ingress`
- One SQLite `PersistentVolumeClaim`
- One chart-managed Secret for `SECRET_KEY_BASE` + `RELEASE_COOKIE`
- Either:
  - one inline runtime Secret from Helm values, or
  - one `ExternalSecret` that syncs runtime credentials from 1Password

## Validation

Lint the chart with CI placeholder values:

```bash
helm lint infra/helm/slack \
  -f infra/helm/slack/values-ci.yaml
```

Render the production manifests:

```bash
helm template slack infra/helm/slack \
  -f infra/helm/slack/values-production.yaml \
  -f infra/helm/slack/values-ci.yaml
```

## Managed-cluster secrets

The production overlay expects one 1Password item named
`SLACK_INVITATION_APP` with these fields:

- `admin-username`
- `admin-password`
- `turnstile-site-key`
- `turnstile-secret-key`
- `mailgun-api-key`
- `slack-invite-url`
- `slack-bot-token`
- `slack-channel-id`

The cluster bootstrap already installs the `onepassword`
`ClusterSecretStore`; this chart only consumes it.

## Manual install

```bash
helm upgrade --install slack infra/helm/slack \
  --namespace slack --create-namespace \
  -f infra/helm/slack/values-production.yaml \
  --set image.tag=<image-tag>
```
