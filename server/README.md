# Tuist Server

This repository contains the source code of the server-side application that extends the functionality of the [Tuist](https://tuist.io) CLI.

## Contributing

Contributions to the Tuist Server require signing a Contributor License Agreement (CLA). Please see [CLA.md](./CLA.md) for details before submitting pull requests that modify server components.

## Development

### Requirements

- [Postgres](https://formulae.brew.sh/formula/postgresql@16)
- [Mise](https://mise.jdx.dev/)

### Set up

1. Clone the repository: `git clone https://github.com/tuist/tuist.git`.
1. Open the folder: `cd server`.
1. Install system dependencies with: `mise install`.
1. Start Postgres with: `brew services start postgresql@16`.
1. Start ClickHouse with: `mise run clickhouse:start`
1. Install dependencies: `mise run install`
1. Create and set up the database: `mise run db:setup`
1. Run the server: `mise run dev`
1. Open the local URL for your current clone or worktree in your browser and log in with the pre-made test user account. With `mise activate` enabled, each checkout persists its own numeric suffix through Git metadata when available, while keeping the existing root `.tuist-dev-instance` file as a compatibility fallback. That suffix scopes the local service ports, MinIO ports, and the PostgreSQL and ClickHouse database names, while the local ClickHouse daemon itself stays shared across checkouts. For example, a suffix of `443` yields `http://localhost:8523`:

```
Email: tuistrocks@tuist.dev
Pass: tuistrocks
```

> [!NOTE]
> First-party developers can load encrypted secrets from `priv/secrets/dev.key`. External contributors don't need this key — the server runs locally without it. OAuth, Stripe, and other third-party integrations will be disabled, but core functionality works.

#### To run additional features
1. Clone the repository: `https://github.com/tuist/tuist.git`.
1. Go to `tuist/examples/xcode/generated_ios_app_with_frameworks`.
1. Change the url in `Tuist.swift` to the local URL for the current clone or worktree, for example `http://localhost:8523`.
1. Run `tuist auth` to authenticate.
1. You are now connected to the local Tuist Server!  You can try running `tuist cache` and see the binaries being uploaded.

### Local Kura Controller

To test the server's controller-backed Kura provisioning path from account settings, use the dev-only `Local Controller (kind)` region.

```bash
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

suffix="${TUIST_DEV_INSTANCE:-0}"
cluster="kura-dev-${suffix}"

kind get clusters | grep -qx "$cluster" || \
  kind create cluster --name "$cluster" --config kura/ops/kind/dev-cluster.yaml

docker build -t ghcr.io/tuist/kura-controller:dev -f infra/kura-controller/Dockerfile .
docker build -t ghcr.io/tuist/kura:dev -f kura/Dockerfile kura
kind load docker-image ghcr.io/tuist/kura-controller:dev --name "$cluster"
kind load docker-image ghcr.io/tuist/kura:dev --name "$cluster"

# Optional controller verification from the repository root.
mise x go@1.25.0 -- go test ./infra/kura-controller/...

kubectl --context "kind-${cluster}" apply -f infra/helm/tuist/crds/kura.tuist.dev_kurainstances.yaml
helm template tuist infra/helm/tuist \
  --show-only templates/kura-controller.yaml \
  --set kuraController.enabled=true \
  --set kuraController.namespace=kura \
  --set kuraController.image.tag=dev \
  --set kuraController.image.pullPolicy=IfNotPresent \
  --set server.enabled=false \
  | kubectl --context "kind-${cluster}" apply -f -
```

When rebuilding the controller with the same `:dev` tag after the initial install, restart the Deployment so kind uses the newly-loaded image:

```bash
kubectl --context "kind-${cluster}" -n kura rollout restart deployment/tuist-tuist-kura-controller
kubectl --context "kind-${cluster}" -n kura rollout status deployment/tuist-tuist-kura-controller
```

Start the server, open the account settings page, and deploy a server in `Local Controller (kind)`.

```bash
cd server
TUIST_KURA_RUNTIME_IMAGE_TAG=dev mise run dev
```

After the controller creates the service, port-forward it:

```bash
port=$((4100 + suffix))
kubectl --context "kind-${cluster}" -n kura port-forward svc/kura-tuist-local-controller "${port}:4000"
curl "http://localhost:${port}/up"
```

### Managed Kura Regions

Managed deployments expose the regions listed in `TUIST_KURA_AVAILABLE_REGIONS`. The production Helm overlay currently sets `eu-central,us-east,us-west`, so account settings can deploy one Kura server per account in any managed region that is not already occupied by that account.

Server deploys build and push `ghcr.io/tuist/kura:<sha-tag>` alongside the Tuist server and Kura controller images. Helm passes that tag as `TUIST_KURA_RUNTIME_IMAGE_TAG`; the reconciler uses it to roll active Kura servers forward in lockstep with the server deploy.

Production maps those product regions to Hetzner-backed workload clusters:

| Product region | Cluster ID | Kubernetes client | Hetzner location |
| --- | --- | --- | --- |
| `eu-central` | `eu-central-1` | in-cluster ServiceAccount on `tuist` | `fsn1` |
| `us-east` | `us-east-1` | `TUIST_KURA_KUBECONFIG_US_EAST_1` | `ash` |
| `us-west` | `us-west-1` | `TUIST_KURA_KUBECONFIG_US_WEST_1` | `hil` |

The regional kubeconfig variables are synced by the production deploy workflow from the `tuist-k8s-production` 1Password vault documents `kubeconfig: kura-us-east-1` and `kubeconfig: kura-us-west-1`. Bootstrap those regional clusters with:

```bash
mise run k8s:bootstrap-workload tuist-kura-us-east production "kubeconfig: kura-us-east-1"
mise run k8s:bootstrap-workload tuist-kura-us-west production "kubeconfig: kura-us-west-1"
```
