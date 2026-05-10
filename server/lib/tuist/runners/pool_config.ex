defmodule Tuist.Runners.PoolConfig do
  @moduledoc """
  Pool config sourced from `RunnerPool` CRs in the runners namespace.

  The chart renders one `RunnerPool` per customer + env entry; this
  module reads them from the apiserver and shapes them into the
  `%{name, owner, labels, runner_group_id, allowed_repos, ...}`
  records the dispatch / webhook flows expect. Making the chart
  the single source of truth keeps server-side and controller-side
  agreement on `name`, `owner`, `labels`, and `runner_group_id`
  by construction — drift between the two used to need both a
  PoolConfig change AND a chart change.

  No `min_warm` plumbing on this side: the controller's
  `RunnerPoolReconciler` is the only consumer of that field, and
  it reads the CR directly. We surface it for completeness so a
  future ops dashboard can render the chart's intent without
  re-reading the cluster.

  Repo-level scoping is delegated to the GitHub org runner
  group's allowlist (`runner_group_id`). GitHub itself refuses
  to dispatch a workflow_job into a runner whose group doesn't
  allowlist the repo. The webhook handler additionally checks
  the optional `allowedRepos` list before creating a Burst
  RunnerAssignment so we don't spend a VM on a workflow_job
  that GitHub would refuse anyway.
  """

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient

  @doc """
  Returns the list of pool configs the runners namespace currently
  declares. Empty list when the apiserver isn't reachable
  (self-hosted / preview / dev) so reconcilers no-op cleanly.
  """
  def pools do
    case K8sClient.list_runner_pools(Environment.runners_namespace()) do
      {:ok, items} -> Enum.map(items, &shape_pool/1)
      {:error, _} -> []
    end
  end

  @doc """
  Looks up a pool by its `name` field. Used by the dispatch flow
  to resolve a SA's `tuist.dev/runner-pool` label into the full
  pool record before minting a JIT.
  """
  def find_by_name(name) when is_binary(name) do
    case K8sClient.get_runner_pool(Environment.runners_namespace(), name) do
      {:ok, cr} -> shape_pool(cr)
      {:error, _} -> nil
    end
  end

  @doc """
  Returns the pool's *dispatch label* — the pool-unique label a
  workflow_job must request before this pool will bind a runner to
  it. By convention it's the last entry in the pool's `labels` list
  (the customer-scoped `tuist-staging-macos` / `tuist-canary-macos`
  / `tuist-macos` tag). Generic GitHub labels like `self-hosted`,
  `macOS`, and `ARM64` are advertised on the runner but are *not*
  authorization boundaries — a workflow that asks for only
  `self-hosted` must NOT consume customer pre-bound capacity.
  """
  def dispatch_label(%{labels: labels}) when is_list(labels) and labels != [] do
    List.last(labels)
  end

  @doc """
  Looks up the pool that should accept a `workflow_job: queued`
  event. Matches on `owner` (case-insensitive) — the org login
  parsed from the webhook's `repository.full_name` — and requires
  the pool's `dispatch_label/1` to be present in the requested
  `runs-on` labels.

  Generic labels like `self-hosted` aren't enough — without the
  pool's customer-scoped tag in the request we return
  `{:error, :no_match}` so unrelated workflows don't consume
  pool capacity.

  `pools_override` is for tests; production callers omit it and
  resolve via `pools/0`.
  """
  def match_for_dispatch(owner, requested_labels, pools_override \\ nil)
      when is_binary(owner) and is_list(requested_labels) do
    needle = String.downcase(owner)
    requested = MapSet.new(requested_labels, &String.downcase/1)
    candidates = pools_override || pools()

    Enum.find_value(candidates, {:error, :no_match}, fn pool ->
      pool_owner = String.downcase(pool.owner)
      tag = pool |> dispatch_label() |> String.downcase()

      if pool_owner == needle and MapSet.member?(requested, tag) do
        {:ok, pool}
      end
    end)
  end

  @doc """
  Repo-allowlist check for a queued workflow_job. Returns `:ok`
  when the pool either declares no allowlist (every repo in the
  org allowed; matches the runner-group default) OR carries the
  given `repo` (case-insensitive). Returns `{:error, :repo_not_allowed}`
  otherwise. Callers (webhook handler) use this to short-circuit
  Burst RunnerAssignment creation when GitHub would refuse to
  dispatch the job to the runner group anyway.
  """
  def repo_allowed?(%{allowed_repos: nil}, _repo), do: :ok
  def repo_allowed?(%{allowed_repos: []}, _repo), do: :ok

  def repo_allowed?(%{allowed_repos: list}, repo) when is_list(list) and is_binary(repo) do
    needle = String.downcase(repo)

    if Enum.any?(list, fn r -> String.downcase(r) == needle end) do
      :ok
    else
      {:error, :repo_not_allowed}
    end
  end

  defp shape_pool(%{"metadata" => %{"name" => name}, "spec" => spec}) do
    %{
      name: name,
      owner: Map.get(spec, "owner", ""),
      labels: Map.get(spec, "labels", []),
      runner_group_id: spec |> Map.get("runnerGroupID") |> normalize_int(),
      allowed_repos: Map.get(spec, "allowedRepos"),
      min_warm: Map.get(spec, "minWarm", 0)
    }
  end

  defp normalize_int(nil), do: nil
  defp normalize_int(v) when is_integer(v), do: v
  defp normalize_int(v) when is_binary(v), do: String.to_integer(v)
end
