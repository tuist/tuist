defmodule Tuist.Threads.MCP do
  @moduledoc """
  Profile MCP tools for Threads. Only Streamable HTTP is supported. Discovery
  is all-or-nothing, and disconnected profile entries are not discovered.

  Tool closures contain identifiers and validated tool metadata, never tokens
  or HTTP sessions. Each invocation opens a new MCP session inside the durable
  external-tool reservation. Every POST reloads credentials, verifies the
  endpoint has not changed, pins public HTTPS and then checks run ownership.
  No provider body or exception is used as an error message.
  """

  alias Condukt.MCP.SSE
  alias Tuist.Accounts.MCPServers
  alias Tuist.Accounts.MCPServers.OAuth
  alias Tuist.Accounts.User
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Threads

  @version "2025-06-18"
  @versions ["2025-06-18", "2025-03-26"]
  @max_body 262_144
  @max_tools 100
  @max_pages 10

  @doc "Returns Condukt inline tools, or a fixed MCP error category."
  def discover(%User{id: user_id} = user, run) do
    with :ok <- ownership(run),
         servers = Enum.filter(MCPServers.list(user), & &1.connected),
         true <- length(servers) <= 25 do
      Enum.reduce_while(servers, {:ok, []}, fn server, {:ok, tools} ->
        state = state(user_id, run, server.id, fingerprint(server.url))

        with {:ok, session} <- initialize(state),
             {:ok, definitions} <- list_tools(session, nil, [], [], 0),
             true <- length(tools) + length(definitions) <= @max_tools do
          {:cont, {:ok, tools ++ Enum.map(definitions, &tool(state, &1))}}
        else
          {:error, _} = error -> {:halt, error}
          _ -> {:halt, {:error, :mcp_limit_exceeded}}
        end
      end)
    else
      {:error, _} = error -> error
      _ -> {:error, :mcp_limit_exceeded}
    end
  rescue
    _ -> {:error, :mcp_unavailable}
  catch
    :exit, _ -> {:error, :mcp_unavailable}
  end

  defp state(user_id, run, server_id, endpoint) do
    %{user_id: user_id, run: run, server_id: server_id, endpoint: endpoint, session: nil, version: @version, next_id: 1}
  end

  defp initialize(state) do
    params = %{protocolVersion: @version, capabilities: %{}, clientInfo: %{name: "Tuist Threads", version: "1.0.0"}}

    with {:ok, %{"protocolVersion" => version, "capabilities" => %{"tools" => tools}}, state}
         when version in @versions and is_map(tools) <- rpc(state, "initialize", params),
         {:ok, _, state} <- rpc(%{state | version: version}, "notifications/initialized", %{}, true) do
      {:ok, state}
    else
      {:error, _} = error -> error
      _ -> {:error, :mcp_invalid_response}
    end
  rescue
    _ -> {:error, :mcp_unavailable}
  catch
    :exit, _ -> {:error, :mcp_unavailable}
  end

  defp list_tools(_state, _cursor, _seen, _tools, @max_pages), do: {:error, :mcp_limit_exceeded}

  defp list_tools(state, cursor, seen, tools, page) do
    params = if cursor, do: %{cursor: cursor}, else: %{}

    with {:ok, %{"tools" => definitions} = result, state} when is_list(definitions) <- rpc(state, "tools/list", params),
         true <- length(tools) + length(definitions) <= @max_tools,
         true <- Enum.all?(definitions, &valid_tool?/1),
         tools = tools ++ definitions,
         names = Enum.map(tools, & &1["name"]),
         true <- length(Enum.uniq(names)) == length(names) do
      case result["nextCursor"] do
        nil ->
          {:ok, tools}

        next when is_binary(next) and byte_size(next) in 1..1024 ->
          if next in seen,
            do: {:error, :mcp_invalid_response},
            else: list_tools(state, next, [next | seen], tools, page + 1)

        _ ->
          {:error, :mcp_invalid_response}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :mcp_invalid_response}
    end
  end

  defp tool(state, definition) do
    remote_name = definition["name"]
    name = "mcp_" <> binary_part(fingerprint({state.server_id, remote_name}), 0, 60)

    schema =
      ExJsonSchema.Schema.resolve(
        Map.put(definition["inputSchema"], "$schema", "http://json-schema.org/draft-07/schema#")
      )

    Condukt.tool(
      name: name,
      description: "External profile MCP tool (untrusted): " <> remote_name <> ". " <> (definition["description"] || ""),
      parameters: definition["inputSchema"],
      call: fn args, _context ->
        # Match repository tools: this ID identifies this admitted invocation,
        # not its arguments, so identical intentional calls remain distinct.
        Threads.call_external_tool(state.run, Ecto.UUID.generate(), name, args, fn ->
          invoke(state, remote_name, args, schema)
        end)
      end
    )
  end

  defp invoke(state, name, args, schema) do
    with true <- is_map(args) and bounded?(args, 12, 2000, 65_536),
         :ok <- ExJsonSchema.Validator.validate(schema, args),
         {:ok, session} <- initialize(state) do
      dispatch_tool(session, name, args)
    else
      {:error, errors} when is_list(errors) -> {:error, :invalid_arguments}
      {:error, category} -> completed_error(category)
      _ -> {:error, :invalid_arguments}
    end
  rescue
    _ -> {:error, :mcp_unavailable}
  catch
    :exit, _ -> {:error, :mcp_unavailable}
  end

  defp dispatch_tool(session, name, args) do
    case rpc(session, "tools/call", %{name: name, arguments: args}) do
      {:ok, %{"content" => content} = result, _state} when is_list(content) ->
        # A successful protocol response, including isError, is definitive.
        # The ledger stores binary results, not transport structs or maps.
        {:ok, JSON.encode!(Map.take(result, ["content", "structuredContent", "isError"]))}

      {:error, {:not_dispatched, category}} ->
        completed_error(category)

      {:error, :mcp_tool_failed} ->
        completed_error(:mcp_tool_failed)

      {:error, _} = error ->
        error

      _ ->
        {:error, :mcp_invalid_response}
    end
  end

  defp completed_error(category) do
    {:ok, JSON.encode!(%{isError: true, content: [%{type: "text", text: Atom.to_string(category)}]})}
  end

  defp rpc(state, method, params, notification \\ false) do
    envelope = %{jsonrpc: "2.0", method: method, params: params}
    envelope = if notification, do: envelope, else: Map.put(envelope, :id, state.next_id)

    case prepare(state) do
      {:ok, credentials, pinned, host} -> dispatch(state, credentials, pinned, host, envelope, notification)
      {:error, category} when method == "tools/call" -> {:error, {:not_dispatched, category}}
      {:error, _} = error -> error
    end
  end

  defp prepare(state) do
    # Refresh may wait on another replica. Ownership must be checked AFTER
    # both that wait and DNS pinning, immediately before the network dispatch.
    with {:ok, credentials} <- credentials(state),
         {:ok, _uri} <- OAuth.https_uri(credentials.url),
         {:ok, pinned, host} <- pin(credentials.url),
         :ok <- ownership(state.run) do
      {:ok, credentials, pinned, host}
    else
      {:error, :invalid_url} -> {:error, :mcp_unsafe_endpoint}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :mcp_unavailable}
  catch
    :exit, _ -> {:error, :mcp_unavailable}
  end

  defp dispatch(state, credentials, pinned, host, envelope, notification) do
    with {:ok, response} <- send_request(pinned, host, credentials.access_token, state, envelope, notification),
         {:ok, session} <- session_id(response.headers, state.session),
         true <- is_nil(session) or not String.contains?(session, credentials.access_token),
         {:ok, result} <- result(response, state.next_id, notification),
         true <- bounded?(result, 24, 20_000, @max_body) do
      # A hostile server can echo the Authorization value even in JSON keys.
      # Strip literal token echoes before any metadata/result leaves this seam.
      {:ok, redact(result, credentials.access_token), %{state | session: session, next_id: state.next_id + 1}}
    else
      {:error, _} = error -> error
      _ -> {:error, :mcp_invalid_response}
    end
  rescue
    _ -> {:error, :mcp_unavailable}
  catch
    :exit, _ -> {:error, :mcp_unavailable}
  end

  defp credentials(state) do
    case MCPServers.credentials(%User{id: state.user_id}, state.server_id) do
      {:ok, %{url: url, access_token: token} = credentials}
      when is_binary(token) and byte_size(token) in 1..65_536 ->
        if fingerprint(url) == state.endpoint and Regex.match?(~r/\A[\x21-\x7E]+\z/, token),
          do: {:ok, credentials},
          else: {:error, :mcp_connection_changed}

      _ ->
        {:error, :mcp_not_connected}
    end
  end

  defp pin(url) do
    case SSRFGuard.pin(url) do
      {:ok, pinned, host} -> {:ok, pinned, host}
      _ -> {:error, :mcp_unsafe_endpoint}
    end
  end

  defp ownership(run) do
    if Threads.owns_run?(run.id, run.attempt), do: :ok, else: {:error, :stale_run}
  end

  defp send_request(url, host, token, state, envelope, notification) do
    headers = [
      {"authorization", "Bearer " <> token},
      {"content-type", "application/json"},
      {"accept", "application/json, text/event-stream"},
      {"mcp-protocol-version", state.version}
    ]

    headers = if state.session, do: [{"mcp-session-id", state.session} | headers], else: headers

    case PinnedHTTP.request("POST", url,
           headers: headers,
           body: JSON.encode!(envelope),
           connect_options: SSRFGuard.connect_options(host) ++ [timeout: 5_000],
           receive_timeout: 10_000,
           total_timeout: 15_000,
           max_body_bytes: @max_body,
           accept_status: [200, 202, 204],
           headers_only: notification,
           into: collector(state.next_id)
         ) do
      {:ok, response} -> {:ok, response}
      {:error, _} -> {:error, :mcp_unavailable}
    end
  end

  defp collector(id) do
    fn {:data, chunk}, {request, response} ->
      body = response.body <> chunk
      response = %{response | body: body}

      cond do
        byte_size(body) > @max_body -> {:halt, {request, %{response | body: ""}}}
        match?({:ok, _}, result(response, id, false)) -> {:halt, {request, response}}
        result(response, id, false) == {:error, :mcp_tool_failed} -> {:halt, {request, response}}
        true -> {:cont, {request, response}}
      end
    end
  end

  defp result(%{status: status}, _id, true) when status in [200, 202, 204], do: {:ok, %{}}

  defp result(%{status: 200, body: body, headers: headers}, id, false)
       when is_binary(body) and byte_size(body) <= @max_body do
    if String.starts_with?(String.downcase(header(headers, "content-type") || ""), "text/event-stream") do
      {events, _} = SSE.feed(SSE.new(), body)

      responses =
        events
        |> Enum.filter(&(&1.event in [nil, "", "message"]))
        |> Enum.map(&decode_envelope(&1.data, id))
        |> Enum.reject(&(&1 == :unrelated))

      case responses do
        [response] -> response
        _ -> {:error, :mcp_invalid_response}
      end
    else
      case decode_envelope(body, id) do
        :unrelated -> {:error, :mcp_invalid_response}
        response -> response
      end
    end
  end

  defp result(_, _, _), do: {:error, :mcp_invalid_response}

  defp decode_envelope(body, id) do
    case JSON.decode(body) do
      {:ok, %{"jsonrpc" => "2.0", "id" => ^id, "result" => %{} = result} = envelope} ->
        if Map.has_key?(envelope, "error"), do: {:error, :mcp_invalid_response}, else: {:ok, result}

      {:ok, %{"jsonrpc" => "2.0", "id" => ^id, "error" => %{"code" => code, "message" => message}} = envelope}
      when is_integer(code) and is_binary(message) ->
        if Map.has_key?(envelope, "result"), do: {:error, :mcp_invalid_response}, else: {:error, :mcp_tool_failed}

      {:ok, %{"jsonrpc" => "2.0", "method" => method} = message} when is_binary(method) ->
        if Map.has_key?(message, "id"), do: {:error, :mcp_invalid_response}, else: :unrelated

      _ ->
        {:error, :mcp_invalid_response}
    end
  end

  defp session_id(headers, previous) do
    case header(headers, "mcp-session-id") do
      nil ->
        {:ok, previous}

      id when is_binary(id) and byte_size(id) in 1..256 ->
        if Regex.match?(~r/\A[\x21-\x7E]+\z/, id), do: {:ok, id}, else: {:error, :mcp_invalid_response}

      _ ->
        {:error, :mcp_invalid_response}
    end
  end

  defp header(headers, key),
    do: Enum.find_value(headers, fn {name, value} -> if String.downcase(name) == key, do: value end)

  defp valid_tool?(%{"name" => name, "inputSchema" => %{"type" => "object"} = schema} = tool)
       when is_binary(name) and byte_size(name) in 1..128 do
    description = tool["description"]

    Regex.match?(~r/\A[a-zA-Z0-9_.-]+\z/, name) and
      (is_nil(description) or (is_binary(description) and byte_size(description) <= 4096)) and
      bounded?(schema, 12, 2000, 32_768) and safe_schema?(schema) and valid_schema?(schema)
  end

  defp valid_tool?(_), do: false

  # No references, custom dialects, or IDs: schema resolution must never invoke
  # a remote resolver. Draft 7 is the supported validation dialect this slice.
  defp safe_schema?(map) when is_map(map) do
    Enum.all?(map, fn {key, value} ->
      key not in ["$ref", "$dynamicRef", "$recursiveRef", "$schema", "$id"] and safe_schema?(value)
    end)
  end

  defp safe_schema?(list) when is_list(list), do: Enum.all?(list, &safe_schema?/1)
  defp safe_schema?(_), do: true

  defp valid_schema?(schema) do
    ExJsonSchema.Schema.resolve(Map.put(schema, "$schema", "http://json-schema.org/draft-07/schema#"))
    true
  rescue
    _ -> false
  end

  defp bounded?(value, depth, nodes, bytes) do
    tree_size(value, depth, nodes) >= 0 and byte_size(JSON.encode!(value)) <= bytes
  end

  defp tree_size(_, depth, _) when depth < 0, do: -1
  defp tree_size(_, _, nodes) when nodes <= 0, do: -1

  defp tree_size(map, depth, nodes) when is_map(map) do
    Enum.reduce_while(map, nodes - 1, fn {key, value}, remaining ->
      if is_binary(key) do
        case tree_size(value, depth - 1, remaining - 1) do
          n when n >= 0 -> {:cont, n}
          _ -> {:halt, -1}
        end
      else
        {:halt, -1}
      end
    end)
  end

  defp tree_size(list, depth, nodes) when is_list(list) do
    Enum.reduce_while(list, nodes - 1, fn value, remaining ->
      case tree_size(value, depth - 1, remaining) do
        n when n >= 0 -> {:cont, n}
        _ -> {:halt, -1}
      end
    end)
  end

  defp tree_size(value, _, nodes) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
    do: nodes - 1

  defp tree_size(_, _, _), do: -1

  defp redact(value, token) when is_binary(value), do: String.replace(value, token, "[REDACTED]")
  defp redact(value, token) when is_list(value), do: Enum.map(value, &redact(&1, token))

  defp redact(value, token) when is_map(value),
    do: Map.new(value, fn {key, item} -> {redact(key, token), redact(item, token)} end)

  defp redact(value, _token), do: value

  defp fingerprint(value), do: :sha256 |> :crypto.hash(:erlang.term_to_binary(value)) |> Base.encode16(case: :lower)
end
