defmodule Atlas.Connections.Connection do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Encrypted.Binary
  alias Atlas.Users.User

  schema "user_connections" do
    field :provider, :string
    field :provider_user_id, :string
    field :account_name, :string
    field :workspace_id, :string
    field :access_token, Binary, redact: true
    field :refresh_token, Binary, redact: true
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :needs_authorization, :boolean, default: false

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :provider_user_id,
      :account_name,
      :workspace_id,
      :access_token,
      :refresh_token,
      :scopes,
      :expires_at,
      :needs_authorization
    ])
    |> validate_required([:user_id, :provider, :provider_user_id, :account_name, :access_token])
    |> validate_inclusion(:provider, ~w(github slack google))
    |> unique_constraint([:user_id, :provider])
  end

  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    not DateTime.after?(expires_at, DateTime.add(DateTime.utc_now(), 120, :second))
  end
end
