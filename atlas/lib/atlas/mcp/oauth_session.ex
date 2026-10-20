defmodule Atlas.MCP.OAuthSession do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Encrypted.Binary
  alias Atlas.Users.User

  @statuses ~w(authorized needs_authorization)

  schema "mcp_oauth_sessions" do
    field :server_name, :string
    field :status, :string, default: "authorized"
    field :access_token, Binary
    field :refresh_token, Binary
    field :client_id, Binary
    field :client_secret, Binary
    field :token_type, :string, default: "Bearer"
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :last_refreshed_at, :utc_datetime
    field :last_error, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :status,
      :access_token,
      :refresh_token,
      :client_id,
      :client_secret,
      :token_type,
      :scopes,
      :expires_at,
      :last_refreshed_at,
      :last_error
    ])
    |> validate_required([:user_id, :server_name, :status, :token_type])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:user_id, :server_name])
  end

  def valid?(%__MODULE__{status: "authorized", access_token: token, expires_at: expires_at})
      when is_binary(token) and not is_nil(expires_at) do
    DateTime.after?(expires_at, refresh_window())
  end

  def valid?(_session), do: false

  def refreshable?(%__MODULE__{status: "authorized", refresh_token: token}) when is_binary(token) and token != "",
    do: true

  def refreshable?(_session), do: false

  def refresh_window do
    DateTime.utc_now() |> DateTime.add(120, :second) |> DateTime.truncate(:second)
  end
end
