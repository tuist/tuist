defmodule LuftServer.Threads.TuistTools do
  @moduledoc "Tuist's read-only MCP tools, using the triggering author's actual scoped OAuth delegation over /mcp."
  alias LuftServer.Threads
  alias LuftServer.Threads.MCP

  @version "2025-06-18"
  @versions [@version, "2025-03-26"]
  @base "/api/me/mcp-servers/transport"

  def tools(thread, message, run) do
    with :ok <- allowed(thread, message, run),
         {:ok, state} <- initialize(thread, message, run),
         {:ok, definitions, _state} <- list_tools(thread, message, run, state, nil, [], [], 0) do
      {:ok,
       for(
         definition <- definitions,
         read_only?(definition),
         do: {definition["name"], tool(thread, message, run, definition)}
       )}
    end
  end

  defp allowed(thread, message, run) do
    case MCP.request(thread, message, run, :get, @base) do
      {:ok, %{"builtin_mcp_allowed" => true}} -> :ok
      _ -> {:error, :tuist_mcp_scope_required}
    end
  end

  defp tool(thread, message, run, definition) do
    remote = definition["name"]
    name = "tuist_" <> remote

    Condukt.tool(
      name: name,
      description:
        "Tuist tool, acting as the person who sent this message. " <>
          (definition["description"] || ""),
      parameters: definition["inputSchema"],
      call: fn args, _ ->
        Threads.call_external_tool(run, Ecto.UUID.generate(), name, args, fn ->
          invoke(thread, message, run, remote, args)
        end)
      end
    )
  end

  defp invoke(thread, message, run, name, args) do
    with true <- is_map(args) and byte_size(Jason.encode!(args)) <= 65_536,
         :ok <- allowed(thread, message, run),
         {:ok, state} <- initialize(thread, message, run),
         {:ok, definitions, state} <- list_tools(thread, message, run, state, nil, [], [], 0),
         definition when not is_nil(definition) <-
           Enum.find(definitions, &(&1["name"] == name and read_only?(&1))) do
      case rpc(thread, message, run, state, "tools/call", %{name: name, arguments: args}) do
        {:ok, %{"content" => content} = result, _} when is_list(content) ->
          output = Jason.encode!(Map.take(result, ["content", "structuredContent", "isError"]))

          if byte_size(output) <= 262_144,
            do: {:ok, output},
            else: MCP.tool_error(:tuist_result_too_large)

        {:error, :tuist_mcp_tool_failed} ->
          MCP.tool_error(:tuist_mcp_tool_failed)

        # Built-ins are read-only. Neither protocol errors nor ambiguous reads
        # are used to bypass the ledger or offered as writes.
        _ ->
          {:error, :tuist_tool_outcome_unknown}
      end
    else
      _ -> MCP.tool_error(:tuist_tool_not_dispatched)
    end
  rescue
    _ -> {:error, :tuist_tool_outcome_unknown}
  end

  defp initialize(thread, message, run) do
    state = %{session: nil, version: @version, id: 1}

    with {:ok, %{"protocolVersion" => version}, state} when version in @versions <-
           rpc(thread, message, run, state, "initialize", %{
             protocolVersion: @version,
             capabilities: %{},
             clientInfo: %{name: "Luft", version: "1.0.0"}
           }),
         {:ok, _, state} <-
           rpc(
             thread,
             message,
             run,
             %{state | version: version},
             "notifications/initialized",
             %{},
             true
           ) do
      {:ok, state}
    else
      _ -> {:error, :tuist_mcp_unavailable}
    end
  end

  defp list_tools(_, _, _, _, _, _, _, 10), do: {:error, :tuist_mcp_limit_exceeded}

  defp list_tools(thread, message, run, state, cursor, seen, definitions, page) do
    with {:ok, %{"tools" => tools} = result, state} when is_list(tools) <-
           rpc(
             thread,
             message,
             run,
             state,
             "tools/list",
             if(cursor, do: %{cursor: cursor}, else: %{})
           ),
         true <-
           length(tools) + length(definitions) <= 2000 and Enum.all?(tools, &MCP.valid_tool?/1),
         definitions = definitions ++ tools,
         true <- length(Enum.uniq_by(definitions, & &1["name"])) == length(definitions) do
      case result["nextCursor"] do
        nil ->
          {:ok, definitions, state}

        next when is_binary(next) and byte_size(next) in 1..1024 ->
          if next in seen,
            do: {:error, :tuist_mcp_invalid_response},
            else:
              list_tools(thread, message, run, state, next, [next | seen], definitions, page + 1)

        _ ->
          {:error, :tuist_mcp_invalid_response}
      end
    else
      _ -> {:error, :tuist_mcp_invalid_response}
    end
  end

  defp rpc(thread, message, run, state, method, params, notification \\ false) do
    envelope = %{jsonrpc: "2.0", method: method, params: params}
    envelope = if notification, do: envelope, else: Map.put(envelope, :id, state.id)

    headers = [
      {"accept", "application/json, text/event-stream"},
      {"mcp-protocol-version", state.version}
    ]

    headers = if state.session, do: [{"mcp-session-id", state.session} | headers], else: headers

    with {:ok, %{body: body, headers: response_headers}} <-
           MCP.request(thread, message, run, :post, "/mcp", json: envelope, headers: headers),
         session = header(response_headers, "mcp-session-id") || state.session,
         true <-
           is_nil(session) or
             (is_binary(session) and byte_size(session) in 1..256 and
                Regex.match?(~r/\A[\x21-\x7E]+\z/, session)),
         {:ok, result} <- decode(body, state.id, notification) do
      {:ok, result, %{state | session: session, id: state.id + 1}}
    else
      {:error, :tuist_mcp_tool_failed} = error -> error
      _ -> {:error, :tuist_mcp_unavailable}
    end
  end

  @doc false
  def response_complete?(body, id),
    do:
      match?({:ok, _}, decode(body, id, false)) or
        decode(body, id, false) == {:error, :tuist_mcp_tool_failed}

  defp decode(_, _, true), do: {:ok, %{}}

  defp decode(body, id, false) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, body} ->
        decode(body, id, false)

      _ ->
        body
        |> String.replace("\r\n", "\n")
        |> String.split("\n\n")
        |> Enum.drop(-1)
        |> Enum.flat_map(fn frame ->
          data =
            frame
            |> String.split("\n")
            |> Enum.filter(&String.starts_with?(&1, "data:"))
            |> Enum.map_join(
              "\n",
              &(&1 |> String.replace_prefix("data:", "") |> String.replace_prefix(" ", ""))
            )

          case Jason.decode(data) do
            {:ok, %{"id" => ^id} = response} -> [decode(response, id, false)]
            _ -> []
          end
        end)
        |> case do
          [result] -> result
          _ -> {:error, :tuist_mcp_invalid_response}
        end
    end
  end

  defp decode(%{"jsonrpc" => "2.0", "id" => id, "result" => %{} = result} = envelope, id, false) do
    if Map.has_key?(envelope, "error"),
      do: {:error, :tuist_mcp_invalid_response},
      else: {:ok, result}
  end

  defp decode(
         %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}} =
           envelope,
         id,
         false
       )
       when is_integer(code) and is_binary(message) do
    if Map.has_key?(envelope, "result"),
      do: {:error, :tuist_mcp_invalid_response},
      else: {:error, :tuist_mcp_tool_failed}
  end

  defp decode(_, _, _), do: {:error, :tuist_mcp_invalid_response}

  defp header(headers, name) when is_map(headers),
    do: headers |> Map.get(name, []) |> List.first()

  defp header(headers, name),
    do:
      Enum.find_value(headers, fn {key, value} -> if String.downcase(key) == name, do: value end)

  defp read_only?(definition), do: get_in(definition, ["annotations", "readOnlyHint"]) == true
end
