defmodule PulseWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  alias Plug.Parsers.ParseError
  alias PulseWeb.MCPRequestGate

  # MCP clients expect a JSON-RPC parse error for an undecodable body. Body
  # parsing fails before routing, so match the path the way the router would.
  def render("400.json", %{conn: %Plug.Conn{path_info: path_info}, reason: %ParseError{}} = assigns) do
    if MCPRequestGate.mcp_path?(path_info),
      do: Pulse.MCP.error_response(nil, -32_700, "Parse error"),
      else: render("400.json", Map.delete(assigns, :reason))
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
