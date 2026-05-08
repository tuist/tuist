defmodule Tuist.Runners.PoolConfig do
  @moduledoc """
  Hardcoded customer pool definitions for v1.

  Each entry says: "GitHub Actions jobs from this `owner/repo` get
  bound to a runner registered with this label set, capped at
  `max_concurrent` parallel jobs, with `min_warm` of those
  always pre-warmed and pre-registered with GitHub for sub-second
  pickup latency."

  When the second customer lands we move this into the database +
  surface it in the dashboard. The shape here is the contract
  that move has to preserve.

  Pool capacity model (hybrid shape 2):
  - `min_warm` — Pods reserved exclusively for this customer.
    The reconciler creates them with the customer's GitHub JIT
    config baked in at create time. They register with GitHub at
    boot and sit as `online + idle` runners; GitHub's dispatcher
    routes queued jobs to them autonomously. Sub-second pickup.
  - `max_concurrent - min_warm` — burst capacity drawn from the
    cluster-wide *shared pool*. Shared Pods boot generic
    (no JIT) and poll the dispatch endpoint; on
    `workflow_job: queued` from any customer with burst
    headroom, the webhook handler picks an idle shared Pod, mints
    JIT for the matching customer, and the Pod registers with
    GitHub. Adds ~5-10s registration latency vs pre-warmed.
  - The cluster-wide shared pool size is
    `sum(max_concurrent) - sum(min_warm)` across pools. Empty
    when every customer's max equals their min.

  The GitHub App installation that authorizes
  `generate-jitconfig` for this pool's repo is resolved
  dynamically by `Tuist.GitHub.App.get_installation_id_for_repo/3`
  at reconcile time — no per-pool config required, and adding a
  customer is just a new entry here (or a row in the v2 DB
  table).

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
            # Repo-allowlisted org runner group — restricts these
            # JIT runners to tuist/tuist regardless of which repo's
            # workflow asks for the labels. Resolved per-env via
            # TUIST_RUNNER_GROUP_ID; nil falls back to GitHub's
            # default group (id=1) which is *every* repo in the
            # org and is wrong for production.
            runner_group_id: env_runner_group_id(),
            min_warm: 1,
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
            runner_group_id: env_runner_group_id(),
            min_warm: 1,
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
            runner_group_id: env_runner_group_id(),
            min_warm: 3,
            max_concurrent: 5
          }
        ]

      _ ->
        []
    end
  end

  @doc """
  Looks up a pool by its `name` field. Used by the reconciler to
  resolve a pool's config when minting a pre-bound Pod's JIT.
  """
  def find_by_name(name) when is_binary(name) do
    Enum.find(pools(), fn p -> p.name == name end)
  end

  @doc """
  Total warm-pool size across all customers for the current env.
  The reconciler keeps this many generic Pods alive in the
  `tuist-runners` namespace.

      iex> Tuist.Runners.PoolConfig.total_warm_target()
      2  # in staging
  """
  def total_warm_target do
    sum_min_warm() + shared_burst_target()
  end

  @doc """
  Sum of pre-bound Pods across all pools. The reconciler keeps
  exactly this many customer-bound Pods alive across the
  cluster (one row in `runner_assignments` per Pod, with
  `pool_name` + `jit_config` set at create time).
  """
  def sum_min_warm do
    pools() |> Enum.map(& &1.min_warm) |> Enum.sum()
  end

  @doc """
  Cluster-wide shared-pool size. Sized so the cluster has enough
  generic warm capacity to satisfy any single customer's burst up
  to their `max_concurrent`. Mathematically:

      sum(max_concurrent) - sum(min_warm)

  Negative would mean min_warm exceeds max_concurrent for some
  pool — caller error in PoolConfig; we floor at 0 so the
  reconciler doesn't try to delete shared Pods.
  """
  def shared_burst_target do
    cap =
      pools()
      |> Enum.map(fn p -> p.max_concurrent - p.min_warm end)
      |> Enum.sum()

    max(0, cap)
  end

  # Reads TUIST_RUNNER_GROUP_ID at runtime so each managed env
  # (staging / canary / production) can point at its own
  # repo-allowlisted runner group without a chart-template fork.
  # Returns nil when unset — the JIT call then falls back to
  # GitHub's default group (id=1, every repo in the org). That
  # default is fine for staging bring-up but should be overridden
  # before canary/production land.
  defp env_runner_group_id do
    case Environment.runner_group_id() do
      nil -> nil
      id when is_integer(id) -> id
    end
  end

  @doc """
  Returns the pool's *dispatch label* — the pool-unique label a
  workflow_job must request before this pool will bind a runner to
  it. By convention it's the last entry in the pool's `labels` list
  (the customer-scoped `tuist-tuist-staging` / `tuist-tuist-canary`
  / `tuist-tuist` tag). Generic GitHub labels like `self-hosted`,
  `macOS`, and `ARM64` are advertised on the runner but are *not*
  authorization boundaries — a workflow that asks for only
  `self-hosted` must NOT consume customer pre-bound capacity.
  """
  def dispatch_label(%{labels: labels}) when is_list(labels) and labels != [] do
    List.last(labels)
  end

  @doc """
  Looks up the pool that should accept a `workflow_job: queued`
  event. Matches on `repository.full_name` (case-insensitive) and
  requires the pool's `dispatch_label/1` to be present in the
  requested `runs-on` labels — *not* a generic intersection. The
  intersection variant (`not MapSet.disjoint?`) was loose enough
  that any tuist/tuist workflow asking for only `self-hosted`
  would consume customer capacity; the dispatch label is the
  authoritative signal for "this job is targeting this pool."

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
      tag = pool |> dispatch_label() |> String.downcase()

      if full == needle and MapSet.member?(requested, tag) do
        {:ok, pool}
      end
    end)
  end
end
