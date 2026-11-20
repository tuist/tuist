defmodule LuftServer.OAuth.Clients do
  @moduledoc "The single registered Luft native client; no dynamic or third-party clients."
  @behaviour Boruta.Oauth.Clients

  alias Boruta.Oauth.Client

  @client_id "6653b77b-b787-4eb2-b955-8380ea5f1478"

  def client_id, do: @client_id

  @impl true
  def get_client(@client_id) do
    %Client{
      id: @client_id,
      name: "Luft",
      confidential: false,
      authorize_scope: true,
      supported_grant_types: ["authorization_code", "refresh_token"],
      # NativeAuth also validates canonical loopback URLs and the port range.
      # Boruta's wildcard matches at least three characters, so short ports
      # must be registered explicitly to support all RFC 8252 loopback ports.
      redirect_uris:
        ["luft://oauth-callback", "http://127.0.0.1:*/callback"] ++
          Enum.map(1..99, &"http://127.0.0.1:#{&1}/callback"),
      pkce: true,
      public_refresh_token: true,
      public_revoke: false,
      enforce_dpop: false,
      access_token_ttl: 3600,
      authorization_code_ttl: 120,
      refresh_token_ttl: 2_592_000,
      signatures_adapter: "Elixir.Boruta.Internal.Signatures"
    }
  end

  def get_client(_id), do: nil

  @impl true
  def get_client_by_did(_did), do: nil

  @impl true
  def public!, do: nil

  @impl true
  def authorized_scopes(_client), do: []
end
