# CI cache configuration

Workflows attach volumes directly with the documented `tuist/cache-volume@v1`
action, then invoke these scripts to configure their build tool. These scripts
never attach or publish volumes themselves.

Bazel retains repository downloads and content-addressed disk outputs under one
volume, not its output base, server or credentials. Use stable per-task keys;
trusted and fork variants share that key. Remote authentication stays independent.
Idle GC targets 12 GiB and seven days (Bazel 7.4+), not a strict build-time quota.

Mix keeps deps/_build together under a readable project/job key. Install Elixir
and Erlang before running mix.sh and fetch dependencies afterward. The identity
marker checks exact Elixir/ERTS versions and the SHA-256 of mix.lock; incompatible
private build state is reset before reuse. Keep the identity version explicit.
MIX_CACHE_IDENTITY may be supplied by focused tests. MIX_DEPS_PATH/MIX_BUILD_ROOT
use resolved physical paths to preserve relative priv/include links. Use one Mix
project per job, or unset these variables before invoking another project.
Reject nonempty paths and existing symlinks; never persist authentication files,
~/.hex or ~/.mix. Preserve explicitly cold setup-server-mix callers.

Run `bash .github/scripts/cache-volumes/mix_test.sh` and actionlint on callers.
The manual Linux Build Cache Benchmark must validate real cold/warm mounts,
retained source markers and compiled path dependencies. Record attachment time
separately; a saved snapshot is not necessarily resident on the selected host.
