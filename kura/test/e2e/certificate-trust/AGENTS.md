# Build-only Linux certificate-trust evidence

`qualify-linux.sh` is an owner qualification entry point, not a publisher or
fleet rollout. It requires an isolated Linux amd64 runner and an absent output
directory. It builds the exact main merge-base and candidate with the same
Bazel options and candidate `Dockerfile.release`/certificate context. It never
logs into a registry, configures a remote cache, publishes or contacts a cluster.

- Preserve the read-only `qualification_only` runtime-workflow branch. Never
  add the publishing job's secrets, package write permission or OIDC to it.
- Preserve ABBA ordering, equal completed work, all four resource axes and
  post-load recovery. Positive deltas outside baseline variation need review;
  successful script execution is not an automatic resource-budget waiver.
- Pass the exact built `metrics.rs` to the harness. Only source-verified lazy
  pressure-transition/artifact-egress/refresh counter families may begin empty; unknown metrics
  still fail. Record the metrics source hash and do not retrofit raw receipts.
- The resource fixture covers local private-peer mTLS, not native-client build
  cost, provider networks, fleet capacity or deployed Sentry/OTLP/Kubernetes.
- Output resource directories contain synthetic private keys. Upload only the
  explicitly allowed public metrics/results, source metadata and candidate
  hashes/image IDs. Never upload runnable binaries or images without separate
  publication approval. Never upload the entire output tree.
- Cleanup only owned temporary sources, local image tags and fixture containers/
  networks. Never prune the daemon, stop another process or shut down Bazel.
- Check Bash syntax/shellcheck, scoped actionlint and
  `node --test test/e2e/provider-topology/{compare,corpus,metric-schema,summarize}.test.mjs` before dispatch.
