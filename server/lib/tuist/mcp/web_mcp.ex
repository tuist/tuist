defmodule Tuist.MCP.WebMCP do
  @moduledoc """
  The tools the website registers with WebMCP for agents built into the
  browser. Those agents receive the tools without the user adding them, so the
  website only offers the documentation and source tools, which do not depend
  on who is asking.
  """

  alias Tuist.MCP.Components.Tools
  alias Tuist.MCP.Server

  @public_tools [Tools.SearchTuist, Tools.SearchTuistCode, Tools.ListTuistFiles, Tools.ReadTuistFile]

  # Keeps whichever of those tools the hosted and feature-flag gates in
  # `Server` already selected. Prompts are not exposed through WebMCP.
  def public_server do
    server = Server.server()
    %{server | tools: Map.filter(server.tools, fn {_name, module} -> module in @public_tools end), prompts: %{}}
  end
end
