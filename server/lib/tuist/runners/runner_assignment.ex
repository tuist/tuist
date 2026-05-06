defmodule Tuist.Runners.RunnerAssignment do
  @moduledoc """
  Persistent record of a runner Pod's lifecycle, from create to
  dispatch to claim.

  Created by `Tuist.Runners.Reconciler` at Pod-create time with
  `pool_name`/`owner`/`repo`/`jit_config` all NULL — only the
  `dispatch_token_hash` is set, so the dispatch endpoint can
  later authenticate the polling Pod.

  Promoted to a customer pool by `Tuist.Runners.Dispatch` when a
  matching `workflow_job: queued` webhook arrives: same row gets
  the JIT config + pool fields filled in.

  Marked `claimed_at` by the dispatch endpoint after the VM
  successfully fetches the JIT config — first poll wins, later
  polls return the same row idempotently.

  Token is stored as a SHA-256 hash so a database leak doesn't
  surface JIT material; comparison is constant-time against the
  hash.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:pod_uid, :string, []}
  @derive {Jason.Encoder, only: [:pod_uid, :pod_name, :pool_name, :owner, :repo, :claimed_at, :inserted_at]}

  schema "runner_assignments" do
    field :pod_name, :string
    field :pool_name, :string
    field :jit_config, :string
    field :dispatch_token_hash, :binary
    field :claimed_at, :utc_datetime_usec
    field :account_id, :integer
    field :owner, :string
    field :repo, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for the row written when a *shared* Pod is first
  created. No pool/JIT yet — those land via `dispatch_changeset/2`
  once a `workflow_job: queued` webhook arrives.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, ~w(pod_uid pod_name dispatch_token_hash)a)
    |> validate_required(~w(pod_uid pod_name dispatch_token_hash)a)
    |> unique_constraint(:pod_uid, name: "runner_assignments_pkey")
  end

  @doc """
  Changeset for the row written when a *pre-bound* Pod is created.
  All fields land at create time — the row's `jit_config` is
  what the polling VM will fetch on its first dispatch poll, so
  the runner registers with GitHub seconds after Pod boot.
  """
  def pre_bound_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, ~w(pod_uid pod_name pool_name jit_config dispatch_token_hash account_id owner repo)a)
    |> validate_required(~w(pod_uid pod_name pool_name jit_config dispatch_token_hash owner repo)a)
    |> unique_constraint(:pod_uid, name: "runner_assignments_pkey")
  end

  @doc """
  Changeset for promoting a Pod from the shared pool into a
  customer's pool. Validates we don't double-dispatch (jit_config
  already set).
  """
  def dispatch_changeset(assignment, attrs) do
    assignment
    |> cast(attrs, ~w(pool_name jit_config account_id owner repo)a)
    |> validate_required(~w(pool_name jit_config owner repo)a)
  end

  @doc """
  Stamps `claimed_at` once the VM has fetched its JIT.
  """
  def claim_changeset(assignment, claimed_at) do
    change(assignment, claimed_at: claimed_at)
  end

  @doc """
  True when the row represents an idle Pod waiting for dispatch.
  """
  def idle?(%__MODULE__{jit_config: nil}), do: true
  def idle?(%__MODULE__{}), do: false
end
