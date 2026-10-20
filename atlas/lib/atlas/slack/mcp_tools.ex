defmodule Atlas.Slack.MCPTools do
  @moduledoc """
  Builds Condukt tools backed by Atlas' in-process MCP server.

  Condukt's generic MCP adapter keeps a persistent client process and each
  inline tool captures that PID. Slack sessions can outlive the streamable HTTP
  connection behind that client, so Atlas' own MCP server is invoked directly
  here while preserving the same user and MCP claims.
  """

  alias Atlas.MCP.Server
  alias Atlas.Users.User

  @list_tools_request %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}

  def tools_for(%User{} = user, claims) when is_map(claims) do
    conn = mcp_conn(user, claims)

    case Server.handle_message(conn, @list_tools_request) do
      %{"result" => %{"tools" => tools}} when is_list(tools) ->
        Enum.map(tools, &inline_tool(conn, &1))

      %{"error" => %{"message" => message}} ->
        {:error, message}

      other ->
        {:error, "Atlas MCP tools/list returned an unexpected response: #{inspect(other)}"}
    end
  end

  defp inline_tool(conn, %{"name" => name} = descriptor) when is_binary(name) do
    Condukt.tool(
      name: name,
      description: Map.get(descriptor, "description", ""),
      parameters: Map.get(descriptor, "inputSchema", %{"type" => "object", "properties" => %{}}),
      call: fn args, _ctx -> call_tool(conn, name, args) end
    )
  end

  defp call_tool(conn, name, args) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => args || %{}}
    }

    conn
    |> Server.handle_message(request)
    |> normalize_response()
  end

  defp normalize_response(%{"result" => %{"isError" => true} = result}), do: {:error, render_content(result)}
  defp normalize_response(%{"result" => %{"content" => _content} = result}), do: {:ok, render_content(result)}
  defp normalize_response(%{"result" => result}), do: {:ok, result}
  defp normalize_response(%{"error" => %{"message" => message}}), do: {:error, message}
  defp normalize_response(%{"error" => error}), do: {:error, inspect(error)}
  defp normalize_response(other), do: {:error, "Unexpected Atlas MCP response: #{inspect(other)}"}

  defp render_content(%{"content" => parts}) when is_list(parts) do
    parts
    |> Enum.map(&render_content_part/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ""
      [single] -> single
      many -> Enum.join(many, "\n")
    end
  end

  defp render_content(other), do: other

  defp render_content_part(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp render_content_part(part), do: JSON.encode!(part)

  defp mcp_conn(%User{} = user, claims) do
    %{assigns: %{current_user: user, mcp_claims: claims, audit_interface: "slack"}}
  end
end
