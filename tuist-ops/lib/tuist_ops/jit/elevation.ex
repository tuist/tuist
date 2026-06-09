defmodule TuistOps.JIT.Elevation do
  @moduledoc """
  A bounded-time grant: a person is authorized for elevated
  impersonation on a specific cluster env. The row IS the JIT
  authorization (no tailnet ACL mutation; the policy
  endpoint reads this table at request time). Lifecycle:
  `active → reverted`. The `RevertWorker` flips the row at
  `expires_at`; `expires_at` is also enforced at the policy
  endpoint so the row going stale never grants access.

  Backed by [priv/repo/migrations/20260603120000_create_tailscale_jit_tables.exs](priv/repo/migrations/20260603120000_create_tailscale_jit_tables.exs).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias TuistOps.JIT.Request

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
