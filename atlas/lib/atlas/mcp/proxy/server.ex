defmodule Atlas.MCP.Proxy.Server do
  @moduledoc """
  Runtime configuration for an upstream MCP server that Atlas can proxy.
  """

  @enforce_keys [:name, :url]
  defstruct [
    :name,
    :url,
    auth_type: :none,
    authorization_url: nil,
    token_url: nil,
    registration_url: nil,
    client_id: nil,
    client_secret: nil,
    scopes: [],
    authorization_params: %{},
    token_headers: [],
    shared_oauth: false,
    shared_oauth_user_email: nil,
    transport: :streamable_http,
    headers: [],
    read_only: false,
    tool_allowlist: [],
    operator_grant_header: nil,
    bearer_token: nil,
    receive_timeout: 15_000
  ]
end
