# Boot shim for `bin/tuist eval`.
#
# The swift-registry-sync pod runs with RELEASE_DISTRIBUTION=none (rel/env.sh.eex
# only enables distribution when the chart supplies TUIST_CLUSTER_DNS_SERVICE +
# POD_IP, which it does for the server Deployment only), so `rpc` and `remote`
# cannot attach to the running node. `eval` starts a separate BEAM instead.
#
# Runtime configuration still runs under `eval`, so Tuist.Registry already has
# the registry bucket and credentials. What's missing is the HTTP stack: ex_aws
# is configured to call through TuistCommon.AWS.Client, which dispatches to a
# Finch instance the application supervisor would normally own.
#
# Deliberately does NOT start :tuist — that would boot Oban in a second BEAM and
# start consuming release jobs alongside the live pod.
#
#   SCRIPT  script to run. A bare filename resolves inside this directory, so
#           `SCRIPT=repair.exs` works against the copy shipped in the release
#           without copying anything into the pod.

{:ok, _} = Application.ensure_all_started(:ex_aws)
{:ok, _} = Application.ensure_all_started(:finch)
{:ok, _} = Application.ensure_all_started(:req)
{:ok, _} = Finch.start_link(name: Application.get_env(:tuist_common, :finch_name, Tuist.Finch))

# EVAL runs a snippet instead of a file, so ad-hoc inspection does not need a
# copy-and-rerun cycle. SCRIPT is still the way to run a repair, because a repair
# should be a reviewed file rather than a shell fragment.
case System.get_env("EVAL") do
  nil ->
    script =
      case System.fetch_env!("SCRIPT") do
        "/" <> _ = absolute -> absolute
        relative -> Application.app_dir(:tuist, Path.join("priv/registry_repair", relative))
      end

    IO.puts("running #{script}")
    Code.eval_file(script)

  code ->
    Code.eval_string(code)
end
