defmodule LuftServer.Sessions.Session do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sessions" do
    field :token_hash, :binary
    field :previous_token_hash, :binary, redact: true
    field :refresh_response, :binary, redact: true
    field :refresh_replay_expires_at, :utc_datetime
    field :user_sub, :string
    field :email, :string
    field :handle, :string
    field :access_token, :binary, redact: true
    field :refresh_token, :binary, redact: true
    field :access_token_expires_at, :utc_datetime
    field :expires_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @fields [
    :token_hash,
    :previous_token_hash,
    :refresh_response,
    :refresh_replay_expires_at,
    :user_sub,
    :email,
    :handle,
    :access_token,
    :refresh_token,
    :access_token_expires_at,
    :expires_at
  ]
  @required [
    :token_hash,
    :user_sub,
    :access_token,
    :refresh_token,
    :access_token_expires_at,
    :expires_at
  ]

  def changeset(session, attrs) do
    session
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> unique_constraint(:token_hash)
  end
end
