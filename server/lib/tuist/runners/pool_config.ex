defmodule Tuist.Runners.PoolConfig do
  @moduledoc """
  Hardcoded customer pool definitions for v1.

  Pools are **org-scoped** and have a single capacity dimension:
  `min_warm`, the count of pre-bound Pods reserved for this
  customer. Pre-bound is the paid sub-second-pickup tier — the
  reconciler keeps that many Pods alive with a JIT pre-minted at
  create time, so they're already `online + idle` on GitHub when
  a workflow_job arrives.

  No `max_concurrent` cap, no shared / burst pool. The other CI
  vendors (Namespace, Blacksmith, WarpBuild, RunsOn) don't expose
  a per-customer concurrency ceiling, and on closer inspection
  the shared-pool concept doesn't carry its weight either:
  bursts above `min_warm` are served by minting an on-demand
  Pod from the dispatch webhook — that's the cold path and pays
  ~30-90 s of clone+boot+register, but it's the same path every
  competitor's "default tier" walks. Adding a shared pre-warmed
  pool sized by aggregate burst is a Phase 2+ optimization for
  when cold-start latency starts mattering at scale.

  Repo-level scoping is delegated to the GitHub org runner
  group's allowlist (`runner_group_id` below). GitHub itself
  refuses to dispatch a workflow_job into a runner whose group
  doesn't allowlist the repo, so we don't reimplement that check.

  When the second customer lands we move this into the database
  + surface it in the dashboard. The shape here is the contract
  that move has to preserve.

  The GitHub App installation that authorizes
  `generate-jitconfig` is resolved per-org by
  `Tuist.GitHub.App.get_installation_id_for_org/2` at reconcile
  time — no per-pool config required, and adding a customer is
  just a new entry here (or a row in the v2 DB table).

  Resolved at runtime by `pools/0` so the per-env values
  overrides (TUIST_DEPLOY_ENV) drive the pool config without a
  redeploy of the chart's Helm values.
  """

  alias Tuist.Environment

  @doc """
  Returns the list of pool configs for the current deploy
  environment. Empty list when runners are off (self-hosted /
  preview / dev) so reconcilers no-op cleanly.

  `min_warm` is the only customer-visible knob — and we don't
  expose it directly today (it's an internal Tuist setting). For
  customers who haven't paid for the sub-second-pickup tier it
  defaults to `0`; their queued jobs spin up an on-demand Pod
  from the webhook handler.
  """
  def pools do
    case Environment.env() do
      :stag ->
        [
          %{
            name: "tuist",
            account_id: nil,
            owner: "tuist",
            labels: ["self-hosted", "macOS", "ARM64", "tuist-staging-macos"],
            # Repo-allowlisted org runner group — restricts these
            # JIT runners to the repos the org admin allowlisted
            # in the runner group, regardless of which workflow
            # asks for the labels. Resolved per-env via
            # TUIST_RUNNER_GROUP_ID; nil falls back to GitHub's
            # default group (id=1) which is *every* repo in the
            # org and is wrong for production.
            runner_group_id: env_runner_group_id(),
            min_warm: 1
          }
        ]

      :can ->
        [
          %{
            name: "tuist",
            account_id: nil,
            owner: "tuist",
            labels: ["self-hosted", "macOS", "ARM64", "tuist-canary-macos"],
            runner_group_id: env_runner_group_id(),
            min_warm: 1
          }
        ]

      :prod ->
        [
          %{
            name: "tuist",
            account_id: nil,
            owner: "tuist",
            labels: ["self-hosted", "macOS", "ARM64", "tuist-macos"],
            runner_group_id: env_runner_group_id(),
            min_warm: 3
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
  Total count of pre-bound Pods the reconciler should keep alive
  across all pools — `sum(min_warm)`. Used by callers that want
  an early-out when the cluster has no pre-warm at all (e.g. a
  freshly bootstrapped self-hosted instance with no customers
  yet).
  """
  def sum_min_warm do
    pools() |> Enum.map(& &1.min_warm) |> Enum.sum()
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

  Repo-level scoping is *not* enforced here; that's the GitHub
  runner group's job (and is configured per-pool via
  `runner_group_id`). A workflow_job from a repo that isn't on
  the runner group's allowlist is rejected by GitHub before it
  reaches a registered runner, so by the time we see the
  `workflow_job: queued` event we already know the repo is
  permitted. Matching on `owner` here keeps the trust boundaries
  in one place (GitHub) instead of duplicating them.

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
end
