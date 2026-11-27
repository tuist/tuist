defmodule LuftServer.MCPServers.Server do
  @moduledoc """
  A remote MCP server and the OAuth session Luft holds for it. `owner` is
  `user:<sub>` or `account:<id>` (see `LuftServer.MCPServers`). The client
  secret, tokens and pending authorization (PKCE verifier) are encrypted and
  redacted from inspection. Only `LuftServer.MCPServers` reads these rows.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias LuftServer.MCPServers.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "mcp_servers" do
    field :owner, :string
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
    field :client_secret, EncryptedBinary, redact: true
    field :access_token, EncryptedBinary, redact: true
    field :refresh_token, EncryptedBinary, redact: true
    field :expires_at, :utc_datetime
    # The lease of the refresh in flight, so concurrent readers share it.
    field :refreshing_until, :utc_datetime
    field :pending_authorization, EncryptedBinary, redact: true
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
    |> validate_required([:owner, :name, :url])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_length(:url, max: 2048)
    |> unique_constraint([:owner, :url])
    |> unique_constraint(:pending_state_hash)
  end
end
