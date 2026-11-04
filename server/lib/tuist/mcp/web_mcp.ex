defmodule Tuist.MCP.WebMCP do
  @moduledoc """
  The tool sets the website registers with WebMCP for agents built into the
  browser. Those agents receive the tools without the user adding them and read
  content that builds and tests produce, so no tool that changes data is
  offered: a signed-in account page gets the read-only tools, limited to that
  account (`Tuist.MCP.Authorization.account_scope/1`), and other pages only
  the documentation and source tools, which do not depend on who is asking.
  """

  alias Tuist.MCP.Components.Tools
  alias Tuist.MCP.Server

  @public_tools [Tools.SearchTuist, Tools.SearchTuistCode, Tools.ListTuistFiles, Tools.ReadTuistFile]

  def account_server, do: restrict(& &1.annotations().readOnlyHint)

  def public_server, do: restrict(&(&1 in @public_tools))

  # Keeps the tools the hosted and feature-flag gates in `Server` already
  # selected. Prompts are not exposed through WebMCP.
  defp restrict(keep?) do
    server = Server.server()
    %{server | tools: Map.filter(server.tools, fn {_name, module} -> keep?.(module) end), prompts: %{}}
  end
end
