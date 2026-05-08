defmodule Tuist.Runners do
  @moduledoc """
  Customer-facing GitHub Actions runners on Tuist's Mac mini fleet.

  Architecture:

  - `Tuist.Runners.Reconciler` keeps `min_warm` pre-bound Pods
    alive per pool. Each Pod is created with a JIT runner config
    minted in advance, plus a `runner_assignments` row carrying
    the dispatch-token hash + JIT material. The polling VM picks
    up the JIT on its first poll and registers with GitHub
    seconds after boot — `online + idle`, ready for a queued job.
  - GitHub's own dispatcher routes `workflow_job: queued` events
    to those `online + idle` runners autonomously. We never see
    the webhook for jobs the pre-bound pool can serve.
  - When pre-bound is saturated, GitHub fires
    `workflow_job: queued` for the unscheduled job. The webhook
    handler (`Tuist.Runners.Dispatch`) creates an on-demand Pod
    for that customer's pool — same shape as a pre-bound Pod,
    just minted reactively. The job pays a ~30-90 s cold-start
    while the VM clones, boots, and registers.
  - Each runner is single-shot: `./run.sh --jitconfig` exits
    after one job, the VM halts, the Watcher (`Tuist.Runners.Watcher`)
    observes the terminal Pod, deletes the Pod + assignment row,
    and (if the pool dropped below `min_warm`) the reconciler
    refills.

  No `pods/patch` or `secrets/*` RBAC required: state lives in
  Postgres; the Pod object is treated as immutable after create.

  See `Tuist.Runners.PoolConfig` for the pool table (hardcoded
  for v1; moves to the database in v2).
  """

  alias Tuist.Repo
  alias Tuist.Runners.RunnerAssignment

  @doc """
  Creates the `runner_assignments` row for a Pod whose JIT was
  minted at create time. Called by both the reconciler (when
  filling the steady-state `min_warm` gap) and the dispatch
  webhook (on-demand for a queued workflow_job beyond the
  pre-bound pool). Same shape either way — the only difference
  is *when* it runs.
  """
  def create_pre_bound_assignment(attrs) do
    attrs
    |> RunnerAssignment.pre_bound_changeset()
    |> Repo.insert()
  end

  @doc """
  Looks up an assignment by Pod UID.
  """
  def get_assignment(pod_uid) when is_binary(pod_uid) do
    Repo.get(RunnerAssignment, pod_uid)
  end

  @doc """
  Removes an assignment row. Used by the watcher's GC when a
  Pod transitions to a terminal phase (Succeeded/Failed) or is
  deleted from the cluster. Idempotent: missing pod_uid returns
  ok.
  """
  def delete_assignment(pod_uid) when is_binary(pod_uid) do
    case Repo.get(RunnerAssignment, pod_uid) do
      nil -> :ok
      assignment -> assignment |> Repo.delete() |> normalize_delete()
    end
  end

  defp normalize_delete({:ok, _}), do: :ok
  defp normalize_delete({:error, _} = err), do: err

  @doc """
  Marks the assignment claimed (the VM has fetched its JIT
  config). Idempotent.
  """
  def claim_assignment(%RunnerAssignment{claimed_at: nil} = assignment) do
    assignment
    |> RunnerAssignment.claim_changeset(DateTime.utc_now())
    |> Repo.update()
  end

  def claim_assignment(%RunnerAssignment{} = assignment), do: {:ok, assignment}

  @doc """
  Constant-time comparison of a presented dispatch token against
  the persisted SHA-256 hash.
  """
  def token_matches?(%RunnerAssignment{dispatch_token_hash: hash}, presented) when is_binary(presented) do
    presented_hash = :crypto.hash(:sha256, presented)
    Plug.Crypto.secure_compare(hash, presented_hash)
  end

  @doc """
  SHA-256 hash of the dispatch token, ready for persistence.
  """
  def hash_token(token) when is_binary(token) do
    :crypto.hash(:sha256, token)
  end
end
