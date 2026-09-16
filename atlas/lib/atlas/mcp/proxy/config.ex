defmodule Atlas.MCP.Proxy.Config do
  @moduledoc """
  Runtime configuration for upstream MCP proxy servers.
  """

  def get do
    Application.get_env(:atlas, :mcp_proxy, [])
  end
end
