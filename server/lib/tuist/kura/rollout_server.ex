defmodule Tuist.Kura.RolloutServer do
  @moduledoc """
  One server's scope in a rollout: the pre-upgrade health baseline captured
  just before its wave scheduled, whether it is eligible for the
  comparative health soak, the deployment minted for the current attempt,
  and when it was observed converged on the target image.

  Scheduling is at-most-once per rollout *attempt* (not per server-tag
  lifetime): `attempt` increments on resume, which mints a fresh
  deployment for every non-converged server — including those whose
  previous attempt failed — so an infrastructure-caused wave failure is
  recoverable without waiting for an unrelated Kura release.

  `soak_eligible` is false for servers that were already unhealthy when
  their wave scheduled: their pre-existing sickness would read as a
  regression they did not cause. They are excluded from the comparative
  soak only — convergence on the target image is still required, because a
  fix must land on degraded servers too.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Rollout
  alias Tuist.Kura.Server

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_rollout_servers" do
    field :wave, :integer
    field :attempt, :integer, default: 0
    field :soak_eligible, :boolean, default: true
    field :baseline_outbox_messages, :integer
    field :baseline_fd_timeout_count, :integer
    field :baseline_peer_connection_failures, :integer
    field :baseline_captured_at, :utc_datetime
    field :converged_at, :utc_datetime

    belongs_to :rollout, Rollout, foreign_key: :kura_rollout_id, type: :binary_id
    belongs_to :kura_server, Server, type: :binary_id
    belongs_to :deployment, Deployment, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(rollout_server \\ %__MODULE__{}, attrs) do
    rollout_server
    |> cast(attrs, [
      :kura_rollout_id,
      :kura_server_id,
      :wave,
      :attempt,
      :soak_eligible,
      :baseline_outbox_messages,
      :baseline_fd_timeout_count,
      :baseline_peer_connection_failures,
      :baseline_captured_at,
      :deployment_id,
      :converged_at
    ])
    |> validate_required([:kura_rollout_id, :kura_server_id, :wave])
    |> validate_number(:wave, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:kura_rollout_id)
    |> foreign_key_constraint(:kura_server_id)
    |> unique_constraint([:kura_rollout_id, :kura_server_id])
  end

  def update_changeset(rollout_server, attrs) do
    rollout_server
    |> cast(attrs, [
      :attempt,
      :soak_eligible,
      :baseline_outbox_messages,
      :baseline_fd_timeout_count,
      :baseline_peer_connection_failures,
      :baseline_captured_at,
      :deployment_id,
      :converged_at
    ])
    |> validate_number(:attempt, greater_than_or_equal_to: 0)
  end
end
