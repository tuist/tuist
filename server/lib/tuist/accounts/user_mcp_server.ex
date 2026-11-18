defmodule Tuist.Accounts.UserMCPServer do
  @moduledoc """
  A remote MCP server a user added for AI features, with the OAuth session
  Tuist holds for it. The client secret, tokens and pending authorization
  (PKCE verifier) are encrypted with `Tuist.Vault` and redacted from
  inspection. Only `Tuist.Accounts.MCPServers` reads these rows.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.User
  alias Tuist.Vault.Binary

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "user_mcp_servers" do
    belongs_to :user, User
    field :name, :string
    field :url, :string
    # The protected resource the tokens are bound to (RFC 8707 `resource`).
    field :resource, :string
    field :issuer, :string
    field :authorization_endpoint, :string
    field :token_endpoint, :string
    field :scope, :string
    # Registered dynamically with the authorization server, reused on reconnect.
    field :client_id, :string
    field :client_secret, Binary, redact: true
    field :access_token, Binary, redact: true
    field :refresh_token, Binary, redact: true
    field :expires_at, :utc_datetime
    # The lease of the refresh in flight, so concurrent readers share it.
    field :refreshing_until, :utc_datetime
    field :pending_authorization, Binary, redact: true
    # SHA-256 of the OAuth `state`, so the callback finds its row.
    field :pending_state_hash, :binary, redact: true
    field :pending_expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(server, attrs) do
    server
    |> cast(attrs, [
      :name,
      :url,
      :resource,
      :issuer,
      :authorization_endpoint,
      :token_endpoint,
      :scope,
      :client_id,
      :client_secret,
      :access_token,
      :refresh_token,
      :expires_at,
      :refreshing_until,
      :pending_authorization,
      :pending_state_hash,
      :pending_expires_at
    ])
    |> validate_required([:user_id, :name, :url])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_length(:url, max: 2048)
    |> unique_constraint([:user_id, :url])
    |> unique_constraint(:pending_state_hash)
  end
end
