defmodule Tuist.Accounts.AgentAuthJTI do
  @moduledoc """
  Replay-protection record for auth.md identity assertions and logout tokens.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "agent_auth_jtis" do
    field :issuer, :string
    field :jti, :string
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:issuer, :jti, :expires_at])
    |> validate_required([:issuer, :jti, :expires_at])
    |> unique_constraint([:issuer, :jti])
  end
end
