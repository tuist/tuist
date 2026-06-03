defmodule Tuist.TailscaleJIT.Elevation do
  @moduledoc """
  A runtime grant: a person has been added to a break-glass
  Tailscale group for a bounded session. Lifecycle:
  `active → reverting → reverted | revert_failed`. The
  `RevertWorker` flips `active → reverted` at `expires_at`; the
  `DriftReconcilerWorker` is the authoritative reaper that catches
  anything Oban missed.

  Backed by [priv/repo/migrations/20260603120000_create_tailscale_jit_tables.exs](priv/repo/migrations/20260603120000_create_tailscale_jit_tables.exs).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.TailscaleJIT.Request

  @statuses ~w(active reverting reverted revert_failed)

  schema "tailscale_jit_elevations" do
    field :requester_email, :string
    field :target_group, :string
    field :expires_at, :utc_datetime
    field :status, :string, default: "active"
    field :reverted_at, :utc_datetime
    field :revert_failure_reason, :string

    belongs_to :request, Request

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:request_id, :requester_email, :target_group, :expires_at])
    |> validate_required([:request_id, :requester_email, :target_group, :expires_at])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:request_id)
  end

  def transition_changeset(elevation, attrs) do
    elevation
    |> cast(attrs, [:status, :reverted_at, :revert_failure_reason])
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
