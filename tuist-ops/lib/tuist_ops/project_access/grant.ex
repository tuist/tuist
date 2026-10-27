defmodule TuistOps.ProjectAccess.Grant do
  @moduledoc """
  A bounded-time capability: an operator may access a specific
  customer account at a tier (`read` or `admin`) until `expires_at`.
  The signed token the customer server verifies offline is derived
  from this row (see `TuistOps.ProjectAccess.Token`); the row itself
  is the audit record and the revocation handle.

  Lifecycle: `active → revoked`. There is no runtime call from the
  customer server back to ops, so revocation before `expires_at` is
  best-effort (the token is a short-TTL bearer); the customer server
  re-checks `exp` on every request and rotating the signing keypair
  is the break-glass that invalidates all outstanding grants at once.

  Backed by [priv/repo/migrations/20260610120000_create_project_access_tables.exs](priv/repo/migrations/20260610120000_create_project_access_tables.exs).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias TuistOps.ProjectAccess.Request

  @statuses ~w(active revoked)

  schema "project_access_grants" do
    field :requester_email, :string
    field :account_handle, :string
    field :tier, :string
    field :reason, :string
    field :expires_at, :utc_datetime
    field :status, :string, default: "active"
    field :revoked_at, :utc_datetime

    belongs_to :request, Request

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:request_id, :requester_email, :account_handle, :tier, :reason, :expires_at])
    |> validate_required([
      :request_id,
      :requester_email,
      :account_handle,
      :tier,
      :reason,
      :expires_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:request_id)
    |> unique_constraint(:request_id)
  end

  def transition_changeset(grant, attrs) do
    grant
    |> cast(attrs, [:status, :revoked_at])
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
