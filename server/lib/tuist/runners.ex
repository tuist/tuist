defmodule Tuist.Runners do
  @moduledoc """
  Customer-facing GitHub Actions runners on Tuist's Mac mini fleet.

  Architecture (shape 2 — dispatch-time binding):

  - The reconciler (`Tuist.Runners.Reconciler`) maintains N
    generic warm Pods in the `tuist-runners` namespace. Each Pod
    creation also INSERTs a `runner_assignments` row carrying the
    Pod's dispatch-token hash. The Pod is "idle" until dispatch
    fills in its `pool_name` / `jit_config`.
  - On GitHub `workflow_job: queued`, `Tuist.Runners.Dispatch.dispatch/2`
    finds an idle row, mints a JIT runner config from GitHub's API
    for the matching pool, and UPDATEs the row.
  - The VM polls `TuistWeb.RunnersController.dispatch/2`, presents
    its per-Pod token, and gets the JIT config back. It runs
    `./run.sh --jitconfig $JIT --ephemeral`, accepts the queued
    job, exits when complete.
  - The reconciler observes the gap on the next 60 s tick and
    creates a replacement.

  No `pods/patch` or `secrets/*` RBAC required: state lives in
  Postgres; the Pod object is treated as immutable after create.

  See `Tuist.Runners.PoolConfig` for the pool table (hardcoded
  for v1; moves to the database in v2).
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.RunnerAssignment

  @doc """
  Creates an idle assignment row for a freshly-spawned warm Pod.
  Called by the reconciler immediately after a successful Pod
  create — the row carries the dispatch-token hash so a later
  GitHub webhook (or a server restart in between) can still
  authenticate the polling Pod.
  """
  def create_idle_assignment(attrs) do
    attrs
    |> RunnerAssignment.create_changeset()
    |> Repo.insert()
  end

  @doc """
  Looks up an assignment by Pod UID.
  """
  def get_assignment(pod_uid) when is_binary(pod_uid) do
    Repo.get(RunnerAssignment, pod_uid)
  end

  @doc """
  Returns idle assignments — Pods sitting in the shared pool
  with no JIT config yet. Used by the dispatch flow to pick a
  Pod to bind.
  """
  def list_idle_assignments do
    Repo.all(from a in RunnerAssignment, where: is_nil(a.jit_config), order_by: [asc: a.inserted_at])
  end

  @doc """
  Promotes a Pod from idle to customer-bound by writing pool +
  JIT config onto its row. Used by `Tuist.Runners.Dispatch`.
  """
  def dispatch_assignment(%RunnerAssignment{} = assignment, attrs) do
    assignment
    |> RunnerAssignment.dispatch_changeset(attrs)
    |> Repo.update()
  end

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
