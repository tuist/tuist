defmodule Tuist.Runners.PoolConfig do
  @moduledoc """
  Pool config sourced from the `runner_pools` table.

  `Tuist.Runners.Pools` is the CRUD context; this module shapes
  the Ecto records into the runtime map the dispatch / webhook
  flows expect. The K8s `RunnerPool` CR is derived state the
  reconciler keeps in sync — the dispatch endpoint reads from the
  DB so it doesn't pay an apiserver round-trip per request.

  Repo-level scoping is delegated to the GitHub org runner
  group's allowlist (`runner_group_id`). GitHub itself refuses to
  dispatch a workflow_job into a runner whose group doesn't
  allowlist the repo. The webhook handler additionally checks the
  optional `allowed_repos` list before creating a Burst
  RunnerAssignment so we don't spend a VM on a workflow_job that
  GitHub would refuse anyway.
  """

  alias Tuist.Runners.Pool
  alias Tuist.Runners.Pools

  @doc """
  Returns all pool configs as runtime-shape maps. Empty list when
  the DB is empty (preview / dev / self-host without runners).
  """
  def pools do
    Enum.map(Pools.list_pools(), &shape/1)
  end

  @doc """
  Returns the cluster's SharedWarm pool config, or nil.
  """
  def shared_warm do
    case Pools.find_shared_warm() do
      nil -> nil
      pool -> shape(pool)
    end
  end

  @doc """
  Looks up a pool by its `name`. Used by the dispatch flow to
  resolve a SA's `tuist.dev/runner-pool` label into the full
  pool record before minting a JIT.
  """
  def find_by_name(name) when is_binary(name) do
    case Pools.get_pool_by_name(name) do
      nil -> nil
      pool -> shape(pool)
    end
  end

  @doc """
  Pool's *dispatch label* — the customer-scoped tag a workflow_job's
  `runs-on` must include. Last entry of `labels` by convention.
  """
  def dispatch_label(%{labels: labels}) when is_list(labels) and labels != [] do
    List.last(labels)
  end

  def dispatch_label(_), do: nil

  @doc """
  Returns the pool that should accept a `workflow_job: queued`
  event. Matches on `owner` (case-insensitive) and requires the
  pool's `dispatch_label/1` to be present in the requested
  `runs-on` labels. SharedWarm pools are excluded — they're not
  customer-facing.

  `pools_override` is for tests; production callers omit it.
  """
  def match_for_dispatch(owner, requested_labels, pools_override \\ nil)
      when is_binary(owner) and is_list(requested_labels) do
    needle = String.downcase(owner)
    requested = MapSet.new(requested_labels, &String.downcase/1)
    candidates = pools_override || pools()

    Enum.find_value(candidates, {:error, :no_match}, fn pool ->
      if pool.role == :customer do
        pool_owner = String.downcase(pool.owner)
        tag = pool |> dispatch_label() |> String.downcase()

        if pool_owner == needle and MapSet.member?(requested, tag) do
          {:ok, pool}
        end
      end
    end)
  end

  @doc """
  Repo-allowlist check for a queued workflow_job. Returns `:ok`
  when the pool either declares no allowlist OR carries the given
  `repo` (case-insensitive); `{:error, :repo_not_allowed}` otherwise.
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

  defp shape(%Pool{} = pool) do
    %{
      name: pool.name,
      role: Pool.role_atom(pool),
      account_id: pool.account_id,
      owner: pool.owner || "",
      labels: pool.labels || [],
      runner_group_id: pool.runner_group_id,
      allowed_repos: pool.allowed_repos,
      min_warm: pool.min_warm || 0
    }
  end
end
