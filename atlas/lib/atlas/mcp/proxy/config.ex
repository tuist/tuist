defmodule Atlas.MCP.Proxy.Config do
  @moduledoc """
  Runtime and administrator-managed configuration for upstream MCP proxy servers.
  """

  alias Atlas.MCP.ServerConfiguration
  alias Atlas.Repo

  def get do
    configured = Application.get_env(:atlas, :mcp_proxy, [])
    managed = Repo.all(ServerConfiguration)

    Keyword.put(configured, :servers, Keyword.get(configured, :servers, []) ++ Enum.map(managed, &as_proxy_config/1))
  end

  defp as_proxy_config(server) do
    Map.take(server, [
      :name,
      :url,
      :auth_type,
      :authorization_url,
      :token_url,
      :registration_url,
      :scopes,
      :read_only
    ])
  end
end
