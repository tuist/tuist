defmodule Tuist.Accounts.AgentAuthCredential do
  @moduledoc """
  A short-lived access token issued from an auth.md identity assertion.

  Only the token identifier is persisted. The signed bearer token itself is
  returned once and is never stored.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.AgentRegistration

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "agent_auth_credentials" do
    field :jti, :string
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :agent_registration, AgentRegistration, type: UUIDv7

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:agent_registration_id, :jti, :expires_at])
    |> validate_required([:agent_registration_id, :jti, :expires_at])
    |> unique_constraint(:jti)
    |> foreign_key_constraint(:agent_registration_id)
  end

  def revoke_changeset(credential, revoked_at) do
    change(credential, revoked_at: revoked_at)
  end
end
