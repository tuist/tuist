defmodule Tuist.Runners.RunnerAssignment do
  @moduledoc """
  Persistent record of a runner Pod's lifecycle, from create to
  claim.

  Created by `Tuist.Runners.Reconciler.create_pre_bound_pod/1`
  immediately after a successful Pod create. The row carries the
  GitHub-issued `jit_config` + the `dispatch_token_hash` so the
  polling VM can authenticate against the dispatch endpoint and
  fetch its JIT on the first poll. Both the reconciler (steady-
  state `min_warm` refill) and the dispatch webhook handler
  (on-demand burst Pod) walk the same code path — the row's
  shape is the same either way.

  `claimed_at` is stamped by the dispatch endpoint after the VM
  successfully fetches the JIT config — first poll wins, later
  polls return the same row idempotently.

  Token is stored as a SHA-256 hash so a database leak doesn't
  surface JIT material; comparison is constant-time against the
  hash.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:pod_uid, :string, []}
  @derive {Jason.Encoder, only: [:pod_uid, :pod_name, :pool_name, :owner, :claimed_at, :inserted_at]}

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
  Changeset for the row written when a pre-bound (or on-demand
  burst) Pod is created. All fields land at create time — the
  row's `jit_config` is what the polling VM fetches on its first
  dispatch poll, so the runner registers with GitHub seconds
  after Pod boot.

  `repo` stays NULL on these rows; pools are org-scoped and the
  customer's runner group's allowlist on the GitHub side is the
  source of truth for which repos can consume capacity.
  """
  def pre_bound_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, ~w(pod_uid pod_name pool_name jit_config dispatch_token_hash account_id owner)a)
    |> validate_required(~w(pod_uid pod_name pool_name jit_config dispatch_token_hash owner)a)
    |> unique_constraint(:pod_uid, name: "runner_assignments_pkey")
  end

  @doc """
  Stamps `claimed_at` once the VM has fetched its JIT.
  """
  def claim_changeset(assignment, claimed_at) do
    change(assignment, claimed_at: claimed_at)
  end
end
