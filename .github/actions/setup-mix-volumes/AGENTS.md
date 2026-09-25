# Mix cache volumes

Install Elixir and Erlang before this action and fetch dependencies afterward.
The caller's key must isolate project and job/configuration. The action also
isolates exact Elixir/ERTS versions and mix.lock contents. Both deps and _build
live beneath one volume, exposed at the project's normal paths by symlinks.
MIX_DEPS_PATH and MIX_BUILD_ROOT point to their resolved physical paths so Mix's
relative priv/include links work for both Hex and sibling path dependencies.
These variables apply to subsequent steps: use one Mix project per job, or unset
them before invoking an unrelated Mix project.
Reject nonempty preexisting directories instead of deleting fetched sources.
Do not cache ~/.hex, ~/.mix or Git authentication configuration.

Preserve explicit server cold-build jobs. Check real cold/warm compilation,
including path dependencies, using the Linux Build Cache Benchmark before
changing the directory layout. Validate callers with actionlint.
