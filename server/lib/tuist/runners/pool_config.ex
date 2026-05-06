defmodule Tuist.Runners.PoolConfig do
  @moduledoc """
  Hardcoded customer pool definitions for v1.

  Each entry says: "GitHub Actions jobs from this `owner/repo` get
  bound to a runner from the shared pool, registered with this
  label set, capped at `max_concurrent` parallel jobs."

  When the second customer lands we move this into the database +
  surface it in the dashboard. The shape here is the contract
  that move has to preserve.

  For v1:
  - `min_warm: 0` — no per-customer pre-bound Pods. Everything
    floats in the shared pool sized at `sum(max_concurrent)`.
  - `max_concurrent` doubles as the customer's published
    concurrency tier: 2 for staging/canary, 5 for production.

  Resolved at runtime by `env/0` so the per-env values
  overrides (TUIST_DEPLOY_ENV) drive the pool config without a
  redeploy of the chart's Helm values.
  """

  alias Tuist.Environment

  @doc """
  Returns the list of pool configs for the current deploy
  environment. Empty list when runners are off (self-hosted /
  preview / dev) so reconcilers no-op cleanly.
  """
  def pools do
    case Environment.env() do
      :stag ->
        [
          %{
            name: "tuist-tuist",
            account_id: nil,
            owner: "tuist",
            repo: "tuist",
            labels: ["self-hosted", "macOS", "ARM64", "tuist-tuist-staging"],
            min_warm: 0,
            max_concurrent: 2
          }
        ]

      :can ->
        [
          %{
            name: "tuist-tuist",
            account_id: nil,
            owner: "tuist",
            repo: "tuist",
            labels: ["self-hosted", "macOS", "ARM64", "tuist-tuist-canary"],
            min_warm: 0,
            max_concurrent: 2
          }
        ]

      :prod ->
        [
          %{
            name: "tuist-tuist",
            account_id: nil,
            owner: "tuist",
            repo: "tuist",
            labels: ["self-hosted", "macOS", "ARM64", "tuist-tuist"],
            min_warm: 0,
            max_concurrent: 5
          }
        ]

      _ ->
        []
    end
  end

  @doc """
  Total warm-pool size across all customers for the current env.
  The reconciler keeps this many generic Pods alive in the
  `tuist-runners` namespace.

      iex> Tuist.Runners.PoolConfig.total_warm_target()
      2  # in staging
  """
  def total_warm_target do
    pools()
    |> Enum.map(fn p -> p.min_warm + p.max_concurrent end)
    |> Enum.sum()
  end

  @doc """
  Looks up the pool that should accept a `workflow_job: queued`
  event. Matches on `repository.full_name` (case-insensitive) and
  the requested `runs-on` labels intersecting the pool's labels.
  Returns `{:ok, pool}` or `{:error, :no_match}`.

  `pools_override` is for tests; production callers omit it and
  resolve via `pools/0`.
  """
  def match_for_dispatch(repo_full_name, requested_labels, pools_override \\ nil)
      when is_binary(repo_full_name) and is_list(requested_labels) do
    needle = String.downcase(repo_full_name)
    requested = MapSet.new(requested_labels, &String.downcase/1)
    candidates = pools_override || pools()

    Enum.find_value(candidates, {:error, :no_match}, fn pool ->
      full = String.downcase("#{pool.owner}/#{pool.repo}")
      pool_labels = MapSet.new(pool.labels, &String.downcase/1)

      if full == needle and not MapSet.disjoint?(pool_labels, requested) do
        {:ok, pool}
      end
    end)
  end
end
