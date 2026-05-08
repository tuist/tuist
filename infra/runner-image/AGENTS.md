# Runner Image

Tart VM image hosted on the **customer-runner Mac mini fleet**
(`tuist.dev/fleet=<runnersFleetName>`). One image, one Tart VM
per Pod, one ephemeral GitHub Actions runner per VM, one job per
runner.

## What's in the image

- `/opt/actions-runner/` — GitHub Actions runner binary (no
  registration; we register at runtime via JIT config).
- `/opt/tuist/inject-env.sh` — reads tart-kubelet's env mount
  (`/Volumes/My Shared Files/env/tuist.env`) into `/etc/tuist.env`.
- `/opt/tuist/dispatch-poll.sh` — polls
  `TUIST_RUNNER_DISPATCH_URL?pod_uid=…&token=…`. While 204 it
  sleeps; on 200 it execs `./run.sh --jitconfig $JIT`.
- `/Library/LaunchDaemons/dev.tuist.runner.plist` — auto-runs
  `inject-env.sh` then `dispatch-poll.sh` on first boot.

## Build

```bash
cd infra/runner-image
packer init runner.pkr.hcl
packer build runner.pkr.hcl
```

CI: `.github/workflows/runner-image.yml` (manual
`workflow_dispatch`, runs on the bare-metal `vm-image-builder`
Mac mini that already serves xcresult-processor builds).

## Deploy to staging

The chart treats `runnersFleet.enabled` as off by default so
the substrate (Mac mini fleet, RBAC, NetworkPolicy) doesn't
land before a runner image is pinned. Once the workflow has
pushed an image:

```bash
RUNNER_DIGEST=$(crane digest ghcr.io/tuist/tuist-runner:<sha>)

helm upgrade tuist infra/helm/tuist \
  -f infra/helm/tuist/values-managed-common.yaml \
  -f infra/helm/tuist/values-managed-staging.yaml \
  --set server.image.tag=$GIT_SHA \
  --set runnersFleet.enabled=true \
  --set runnersFleet.runnerImage="ghcr.io/tuist/tuist-runner@${RUNNER_DIGEST}"
```

`--set runnersFleet.runnerImage` is digest-pinned in production
so a registry retag of the floating tag can't smuggle in a
different image at runner-Pod create time.

## Verifying end-to-end

1. After deploy, watch `kubectl get pods -n tuist-runners
   -l tuist.dev/runner=true -w`. Two Pods should appear within
   one minute (the staging tier's `runnersFleet.replicas: 2`).
2. Each Pod should reach `Running` once tart-kubelet on its host
   has the VM up.
3. `select * from runner_assignments` in the staging Postgres
   should show two rows with `jit_config IS NULL`,
   `dispatch_token_hash IS NOT NULL`.
4. Trigger `.github/workflows/runners-staging-smoke.yml` from the
   Actions UI. The job has `runs-on: tuist-staging-macos`.
5. Within a few seconds: GH fires `workflow_job: queued`, the
   server's webhook handler binds an idle Pod, the VM polls and
   gets the JIT, the runner registers and runs the job.
6. After the job exits, the Pod transitions to `Completed`. Next
   reconcile cycle (≤ 60 s) creates a fresh Pod.
