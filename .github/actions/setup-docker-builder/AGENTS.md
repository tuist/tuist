# Docker builder action

Composite integration with Docker's upstream setup action. It uses a stable,
hashed workload key and explicitly labels the local BuildKit volume for retention
by the Linux DinD supervisor. `keep-state: true` is required: upstream cleanup
otherwise deletes the volume before the runner's teardown can preserve it.

The action lives in this repository; there is no standalone distribution yet.
Keep it usable as `tuist/tuist/.github/actions/setup-docker-builder@<ref>` with
the standard `docker/build-push-action`. Do not retain arbitrary Docker volumes.
Run the real Docker persistence suite in `infra/linux-runner-image` when changing
the volume naming, label, cleanup or BuildKit configuration.
