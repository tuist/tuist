# Persistent Docker builds on Tuist Linux runners

Use the Tuist builder setup with the standard Docker build action:

```yaml
- uses: actions/checkout@v4
- uses: tuist/tuist/.github/actions/setup-docker-builder@main
  with:
    cache-key: services/api/Dockerfile
- uses: docker/build-push-action@v6
  with:
    context: services/api
    push: true
    tags: ghcr.io/example/api:latest
```

Pin the setup action to a reviewed commit for reproducible workflows.
Docker image caching must be enabled on the runner fleet, with a runner image
containing BuildKit-volume retention. Older images still build successfully but
do not retain this builder's cache between jobs.

Each key identifies a BuildKit state volume within the repository's Docker cache.
Use stable keys per Dockerfile or related image set, shared across branches. Do not
include the commit or lockfile hash. Layers and `RUN --mount=type=cache` contents
both survive successful cache publication. The default BuildKit garbage collection
targets approximately 10 GB per builder; `buildkitd-config-inline` can override it.
The repository's overall Docker cache capacity and publication limits still apply.

The action uses Docker's `docker-container` driver with a stable builder name and
`keep-state: true`. Ordinary service containers and their volumes are removed.
Without an available Docker cache, the build runs with job-local state.

Concurrent jobs use private copies. Different builder keys are preserved when
merging; concurrent writes to one key select one complete builder state, not a
record-level union. A cache miss is always possible. Never use cache mounts as
the only copy of required build outputs or to store credentials.

Builds using the daemon's `docker` driver also retain its build cache without this
action. A separate builder created by `docker/setup-buildx-action` with its default
random name and cleanup does not gain persistent state automatically.
