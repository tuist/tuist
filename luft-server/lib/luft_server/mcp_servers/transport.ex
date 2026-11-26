defmodule LuftServer.MCPServers.Transport do
  @moduledoc """
  Streamable HTTP client for MCP servers in `LuftServer.MCPServers`, owning
  their credentials: no access token leaves this module, and responses have
  it redacted.

  Discovery checks every tool on its own. A tool that breaks a rule is
  dropped and reported with the rule, so one malformed tool never hides the
  rest of a server's catalog. The catalog as a whole is still bounded.
  """

  alias LuftServer.MCPServers
  alias LuftServer.MCPServers.HTTP

  require Logger

  @version "2025-06-18"
  @versions [@version, "2025-03-26"]
  @body_limit 262_144
  @catalog_limit 4_194_304
  @max_tools 2000
  @max_pages 10

  @doc """
  Lists the server's tools. Returns `{:ok, tools, dropped}`, where `dropped`
  holds `{name, rule}` for every tool left out and why.
  """
  def discover(owner, id, authorized?) do
    with {:ok, state} <- initialize(state(owner, id, authorized?)),
         {:ok, tools, dropped, _state} <- list_tools(state, nil, [], {[], MapSet.new()}, [], 0) do
      {:ok, tools, dropped}
    end
  rescue
    _ -> {:error, :mcp_unavailable}
  catch
    :exit, _ -> {:error, :mcp_unavailable}
  end

  @doc """
  Calls a tool in its own protocol session. Failures before `tools/call` are
  definitive non-effects, returned as tool errors; after dispatch only a
  matching JSON-RPC response proves the outcome, so anything else is
  `{:error, :mcp_outcome_unknown}` and must not be retried.
  """
  def call(owner, id, name, args, authorized?) do
    with true <-
           is_binary(name) and byte_size(name) in 1..128 and is_map(args) and
             bounded?(args, 12, 2000, 65_536),
         {:ok, state} <- initialize(state(owner, id, authorized?)),
         {:ok, definitions, _dropped, state} <-
           list_tools(state, nil, [], {[], MapSet.new()}, [], 0),
         %{} = definition <- Enum.find(definitions, &(&1["name"] == name)),
         {:ok, root} <- JSV.build(definition["inputSchema"], default_meta: draft7()),
         {:ok, _} <- JSV.validate(args, root) do
      case rpc(state, "tools/call", %{name: name, arguments: args}) do
        {:ok, %{"content" => content} = result, _} when is_list(content) ->
          {:ok, Map.take(result, ["content", "structuredContent", "isError"])}

        {:error, :mcp_tool_failed} ->
          {:ok, tool_error(:mcp_tool_failed)}

        {:error, {:not_dispatched, category}} ->
          {:ok, tool_error(category)}

        _ ->
          {:error, :mcp_outcome_unknown}
      end
    else
      _ -> {:ok, tool_error(:mcp_not_dispatched)}
    end
  rescue
    # Exceptions may contain private transport data. Never serialize them or
    # turn an exception after a possible dispatch into a retryable non-effect.
    _ -> {:error, :mcp_outcome_unknown}
  catch
    :exit, _ -> {:error, :mcp_outcome_unknown}
  end

  @doc "Returns `:ok`, or `{:error, rule}` naming the first rule the tool breaks."
  def check_tool(%{} = tool) do
    name = tool["name"]
    schema = tool["inputSchema"]
    description = tool["description"]

    cond do
      not (is_binary(name) and byte_size(name) in 1..128) ->
        {:error, "name missing or over 128 bytes"}

      not Regex.match?(~r/\A[a-zA-Z0-9_.-]+\z/, name) ->
        {:error, "name has characters outside a-z A-Z 0-9 _ . -"}

      not (is_nil(description) or is_binary(description)) ->
        {:error, "description is not text"}

      is_binary(description) and byte_size(description) > 4096 ->
        {:error, "description over 4096 bytes"}

      not match?(%{"type" => "object"}, schema) ->
        {:error, "inputSchema is not an object schema"}

      tree_size(schema, 12, 2000) < 0 ->
        {:error, "inputSchema deeper than 12 levels or over 2000 nodes"}

      byte_size(Jason.encode!(schema)) > 32_768 ->
        {:error, "inputSchema over 32768 bytes"}

      not safe_schema?(schema) ->
        {:error, "inputSchema uses $ref, $schema or $id"}

      not valid_schema?(schema) ->
        {:error, "inputSchema is not a valid JSON Schema"}

      true ->
        :ok
    end
  end

  def check_tool(_tool), do: {:error, "not an object"}

  defp state(owner, id, authorized?),
    do: %{
      owner: owner,
      id: id,
      authorized?: authorized?,
      session: nil,
      version: @version,
      next_id: 1
    }

  defp initialize(state) do
    with {:ok, %{"protocolVersion" => version, "capabilities" => %{"tools" => tools}}, state}
         when version in @versions and is_map(tools) <-
           rpc(state, "initialize", %{
             protocolVersion: @version,
             capabilities: %{},
             clientInfo: %{name: "Luft", version: "1.0.0"}
           }),
         {:ok, _, state} <-
           rpc(%{state | version: version}, "notifications/initialized", %{}, true) do
      {:ok, state}
    else
      {:error, _} = error ->
        error

      _ ->
        log_failure(state, "initialize unsupported protocol version or no tools capability")
        {:error, :mcp_invalid_response}
    end
  end

  defp list_tools(state, _, _, _, _, @max_pages) do
    log_failure(state, "tools/list over #{@max_pages} pages")
    {:error, :mcp_limit_exceeded}
  end

  # `kept` holds the valid tools so far, newest first, and their names.
  defp list_tools(state, cursor, seen, kept, dropped, page) do
    with {:ok, %{"tools" => definitions} = result, state} when is_list(definitions) <-
           rpc(state, "tools/list", if(cursor, do: %{cursor: cursor}, else: %{})),
         # Checked before any tool is, so a hostile page can't cost more
         # than the limit's worth of schema compilation.
         true <- length(elem(kept, 0)) + length(definitions) + length(dropped) <= @max_tools do
      {kept, dropped} = sort_tools(definitions, kept, dropped)

      case result["nextCursor"] do
        nil ->
          {:ok, Enum.reverse(elem(kept, 0)), Enum.reverse(dropped), state}

        next when is_binary(next) and byte_size(next) in 1..1024 ->
          if next in seen do
            log_failure(state, "tools/list repeated a cursor")
            {:error, :mcp_invalid_response}
          else
            list_tools(state, next, [next | seen], kept, dropped, page + 1)
          end

        _ ->
          log_failure(state, "tools/list returned an invalid cursor")
          {:error, :mcp_invalid_response}
      end
    else
      {:error, _} = error ->
        error

      false ->
        log_failure(state, "tools/list returned over #{@max_tools} tools")
        {:error, :mcp_limit_exceeded}

      _ ->
        log_failure(state, "tools/list returned no tool list")
        {:error, :mcp_invalid_response}
    end
  end

  # Valid tools are kept in order; a tool reusing a kept name is dropped too.
  defp sort_tools(definitions, kept, dropped) do
    Enum.reduce(definitions, {kept, dropped}, fn definition, {{tools, names} = kept, dropped} ->
      result =
        with :ok <- check_tool(definition) do
          if MapSet.member?(names, definition["name"]),
            do: {:error, "name repeats an earlier tool"},
            else: :ok
        end

      case result do
        :ok -> {{[definition | tools], MapSet.put(names, definition["name"])}, dropped}
        {:error, rule} -> {kept, [{label(definition), rule} | dropped]}
      end
    end)
  end

  # Names are logged, so only a bounded, printable prefix of one.
  defp label(%{"name" => name}) when is_binary(name) and name != "" do
    name |> String.replace(~r/[^\x21-\x7E]/, "?") |> String.slice(0, 64)
  end

  defp label(_definition), do: "(unnamed)"

  defp rpc(state, method, params, notification \\ false) do
    envelope = %{jsonrpc: "2.0", method: method, params: params}
    envelope = if notification, do: envelope, else: Map.put(envelope, :id, state.next_id)

    case prepare(state) do
      {:ok, credentials} -> dispatch(state, credentials, envelope, notification)
      {:error, category} when method == "tools/call" -> {:error, {:not_dispatched, category}}
      error -> error
    end
  end

  # Each step is tagged so a failure logs which check refused.
  defp prepare(state) do
    with {:credentials, {:ok, %{url: url, access_token: token} = credentials}} <-
           {:credentials, MCPServers.credentials(state.owner, state.id)},
         {:token, true} <-
           {:token,
            is_binary(token) and byte_size(token) in 1..65_536 and
              Regex.match?(~r/\A[\x21-\x7E]+\z/, token)},
         {:https, {:ok, _}} <- {:https, MCPServers.OAuth.https_uri(url)},
         {:authorized, true} <- {:authorized, state.authorized?.()} do
      {:ok, credentials}
    else
      {step, result} ->
        log_failure(state, "#{step} #{describe(result)}")
        {:error, :mcp_not_connected}
    end
  rescue
    error ->
      log_failure(state, "prepare raised #{inspect(error.__struct__)}")
      {:error, :mcp_unavailable}
  catch
    :exit, _ ->
      log_failure(state, "prepare exited")
      {:error, :mcp_unavailable}
  end

  defp dispatch(state, credentials, envelope, notification) do
    max_body = if envelope.method == "tools/list", do: @catalog_limit, else: @body_limit

    headers = [
      {"authorization", "Bearer " <> credentials.access_token},
      {"content-type", "application/json"},
      {"accept", "application/json, text/event-stream"},
      {"mcp-protocol-version", state.version}
    ]

    headers = if state.session, do: [{"mcp-session-id", state.session} | headers], else: headers

    with {:ok, response} <-
           HTTP.request("POST", credentials.url,
             headers: headers,
             body: Jason.encode!(envelope),
             receive_timeout: 10_000,
             total_timeout: 15_000,
             max_body_bytes: max_body,
             accept_status: [200, 202, 204],
             headers_only: notification,
             into: collector(state.next_id, max_body)
           ),
         {:ok, session} <- session_id(response.headers, state.session),
         true <- is_nil(session) or not String.contains?(session, credentials.access_token),
         {:ok, result} <- result(response, state.next_id, notification, max_body),
         true <- bounded?(result, 24, 200_000, max_body) do
      {:ok, redact(result, credentials.access_token),
       %{state | session: session, next_id: state.next_id + 1}}
    else
      {:error, :mcp_tool_failed} = error ->
        error

      failure ->
        log_failure(state, "#{envelope.method} #{describe(failure)}")
        {:error, :mcp_unavailable}
    end
  rescue
    # A raise after the request went out is still an unknown outcome to
    # `call/5`, which maps every non-matching reply to `:mcp_outcome_unknown`.
    error ->
      log_failure(state, "#{envelope.method} raised #{inspect(error.__struct__)}")
      {:error, :mcp_unavailable}
  catch
    :exit, _ ->
      log_failure(state, "#{envelope.method} exited")
      {:error, :mcp_unavailable}
  end

  # Only the failure's category: error terms can hold URLs, headers or bodies.
  defp log_failure(state, reason),
    do: Logger.warning("MCP server #{state.id} of #{state.owner} failed: #{reason}")

  defp describe({:error, {:unexpected_status, status}}) when is_integer(status),
    do: "status #{status}"

  defp describe({:error, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(false), do: "refused"
  defp describe(_), do: "invalid"

  defp collector(id, limit) do
    fn {:data, chunk}, {request, response} ->
      response = %{response | body: response.body <> chunk}

      case result(response, id, false, limit) do
        {:ok, _} ->
          {:halt, {request, response}}

        {:error, :mcp_tool_failed} ->
          {:halt, {request, response}}

        _ ->
          if byte_size(response.body) > limit,
            do: {:halt, {request, %{response | body: ""}}},
            else: {:cont, {request, response}}
      end
    end
  end

  defp result(%{status: status}, _, true, _) when status in [200, 202, 204], do: {:ok, %{}}

  defp result(%{status: 200, body: body, headers: headers}, id, false, limit)
       when is_binary(body) and byte_size(body) <= limit do
    content_type = String.downcase(header(headers, "content-type") || "")

    if String.starts_with?(content_type, "text/event-stream") do
      body
      |> String.replace("\r\n", "\n")
      |> String.split("\n\n")
      |> Enum.drop(-1)
      |> Enum.flat_map(&decode_frame(&1, id))
      |> Enum.reject(&(&1 == :unrelated))
      |> case do
        [response] -> response
        _ -> {:error, :mcp_invalid_response}
      end
    else
      case decode(body, id) do
        :unrelated -> {:error, :mcp_invalid_response}
        response -> response
      end
    end
  end

  defp result(_, _, _, _), do: {:error, :mcp_invalid_response}

  defp decode_frame(frame, id) do
    lines = String.split(frame, "\n")

    event =
      Enum.find_value(lines, fn line ->
        if String.starts_with?(line, "event:"),
          do: String.trim(String.replace_prefix(line, "event:", ""))
      end)

    data =
      lines
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map_join("\n", fn line ->
        line |> String.replace_prefix("data:", "") |> String.replace_prefix(" ", "")
      end)

    if event in [nil, "", "message"] and data != "", do: [decode(data, id)], else: []
  end

  defp decode(body, id) do
    case Jason.decode(body) do
      {:ok, %{"jsonrpc" => "2.0", "id" => ^id, "result" => %{} = result} = envelope} ->
        if Map.has_key?(envelope, "error"),
          do: {:error, :mcp_invalid_response},
          else: {:ok, result}

      {:ok,
       %{"jsonrpc" => "2.0", "id" => ^id, "error" => %{"code" => code, "message" => message}} =
           envelope}
      when is_integer(code) and is_binary(message) ->
        if Map.has_key?(envelope, "result"),
          do: {:error, :mcp_invalid_response},
          else: {:error, :mcp_tool_failed}

      {:ok, %{"jsonrpc" => "2.0", "method" => method} = envelope} when is_binary(method) ->
        if Map.has_key?(envelope, "id"), do: {:error, :mcp_invalid_response}, else: :unrelated

      _ ->
        {:error, :mcp_invalid_response}
    end
  end

  defp session_id(headers, previous) do
    case header(headers, "mcp-session-id") do
      nil ->
        {:ok, previous}

      id when is_binary(id) and byte_size(id) in 1..256 ->
        if Regex.match?(~r/\A[\x21-\x7E]+\z/, id),
          do: {:ok, id},
          else: {:error, :mcp_invalid_response}

      _ ->
        {:error, :mcp_invalid_response}
    end
  end

  defp header(headers, key),
    do:
      Enum.find_value(headers, fn {name, value} ->
        if String.downcase(name) == key, do: value
      end)

  defp safe_schema?(map) when is_map(map),
    do:
      Enum.all?(map, fn {key, value} ->
        key not in ["$ref", "$dynamicRef", "$recursiveRef", "$schema", "$id"] and
          safe_schema?(value)
      end)

  defp safe_schema?(list) when is_list(list), do: Enum.all?(list, &safe_schema?/1)
  defp safe_schema?(_), do: true

  defp valid_schema?(schema), do: match?({:ok, _}, JSV.build(schema, default_meta: draft7()))

  defp draft7, do: "http://json-schema.org/draft-07/schema#"

  defp bounded?(value, depth, nodes, bytes),
    do: tree_size(value, depth, nodes) >= 0 and byte_size(Jason.encode!(value)) <= bytes

  defp tree_size(_, depth, _) when depth < 0, do: -1
  defp tree_size(_, _, nodes) when nodes <= 0, do: -1

  defp tree_size(map, depth, nodes) when is_map(map),
    do:
      Enum.reduce_while(map, nodes - 1, fn {key, value}, left ->
        next = if is_binary(key), do: tree_size(value, depth - 1, left - 1), else: -1
        if next >= 0, do: {:cont, next}, else: {:halt, -1}
      end)

  defp tree_size(list, depth, nodes) when is_list(list),
    do:
      Enum.reduce_while(list, nodes - 1, fn value, left ->
        next = tree_size(value, depth - 1, left)
        if next >= 0, do: {:cont, next}, else: {:halt, -1}
      end)

  defp tree_size(value, _, nodes)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: nodes - 1

  defp tree_size(_, _, _), do: -1

  defp redact(value, token) when is_binary(value), do: String.replace(value, token, "[REDACTED]")
  defp redact(value, token) when is_list(value), do: Enum.map(value, &redact(&1, token))

  defp redact(value, token) when is_map(value),
    do: Map.new(value, fn {key, item} -> {redact(key, token), redact(item, token)} end)

  defp redact(value, _), do: value

  defp tool_error(category),
    do: %{isError: true, content: [%{type: "text", text: Atom.to_string(category)}]}
end
