defmodule Tuist.Accounts.MCPServers.Transport do
  @moduledoc "Credential-owning Streamable HTTP capability. No conversation state or credentials leave this module."

  alias Tuist.Accounts.MCPServers
  alias Tuist.Accounts.MCPServers.OAuth
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard

  require Logger

  @version "2025-06-18"
  @versions [@version, "2025-03-26"]
  @body_limit 262_144
  @catalog_limit 4_194_304

  def fingerprint(value), do: :sha256 |> :crypto.hash(:erlang.term_to_binary(value)) |> Base.encode16(case: :lower)

  def connections(user) do
    Enum.map(
      MCPServers.list(user),
      &Map.take(Map.put(&1, :endpoint, fingerprint(&1.url)), [:id, :name, :connected, :endpoint])
    )
  end

  def discover(user, id, endpoint, authorized?) do
    with {:ok, state} <- initialize(state(user, id, endpoint, authorized?)),
         {:ok, tools, _state} <- list_tools(state, nil, [], [], 0) do
      {:ok, tools}
    end
  rescue
    _ -> {:error, :mcp_unavailable}
  catch
    :exit, _ -> {:error, :mcp_unavailable}
  end

  # A call opens its own protocol session. All failures before tools/call are
  # definitive non-effects; after dispatch only a matching JSON-RPC response
  # proves the outcome. The caller must retain ambiguous effects, not retry.
  def call(user, id, endpoint, name, args, authorized?) do
    with true <- is_binary(name) and byte_size(name) in 1..128 and is_map(args) and bounded?(args, 12, 2000, 65_536),
         {:ok, state} <- initialize(state(user, id, endpoint, authorized?)),
         {:ok, definitions, state} <- list_tools(state, nil, [], [], 0),
         definition when not is_nil(definition) <- Enum.find(definitions, &(&1["name"] == name)),
         :ok <- ExJsonSchema.Validator.validate(ExJsonSchema.Schema.resolve(definition["inputSchema"]), args) do
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

  defp state(user, id, endpoint, authorized?),
    do: %{user: user, id: id, endpoint: endpoint, authorized?: authorized?, session: nil, version: @version, next_id: 1}

  defp initialize(state) do
    with {:ok, %{"protocolVersion" => version, "capabilities" => %{"tools" => tools}}, state}
         when version in @versions and is_map(tools) <-
           rpc(state, "initialize", %{
             protocolVersion: @version,
             capabilities: %{},
             clientInfo: %{name: "Tuist", version: "1.0.0"}
           }),
         {:ok, _, state} <- rpc(%{state | version: version}, "notifications/initialized", %{}, true) do
      {:ok, state}
    else
      {:error, _} = error ->
        error

      _ ->
        log_failure(state, "initialize unsupported protocol version or no tools capability")
        {:error, :mcp_invalid_response}
    end
  end

  defp list_tools(_, _, _, _, 10), do: {:error, :mcp_limit_exceeded}

  defp list_tools(state, cursor, seen, tools, page) do
    with {:ok, %{"tools" => definitions} = result, state} when is_list(definitions) <-
           rpc(state, "tools/list", if(cursor, do: %{cursor: cursor}, else: %{})),
         true <- length(tools) + length(definitions) <= 2000 and Enum.all?(definitions, &valid_tool?/1),
         tools = tools ++ definitions,
         true <- length(Enum.uniq_by(tools, & &1["name"])) == length(tools) do
      case result["nextCursor"] do
        nil ->
          {:ok, tools, state}

        next when is_binary(next) and byte_size(next) in 1..1024 ->
          if next in seen,
            do: {:error, :mcp_invalid_response},
            else: list_tools(state, next, [next | seen], tools, page + 1)

        _ ->
          {:error, :mcp_invalid_response}
      end
    else
      {:error, _} = error ->
        error

      _ ->
        log_failure(state, "tools/list returned an invalid or oversized catalog")
        {:error, :mcp_invalid_response}
    end
  end

  defp rpc(state, method, params, notification \\ false) do
    envelope = %{jsonrpc: "2.0", method: method, params: params}
    envelope = if notification, do: envelope, else: Map.put(envelope, :id, state.next_id)

    case prepare(state) do
      {:ok, credentials, pinned, host} -> dispatch(state, credentials, pinned, host, envelope, notification)
      {:error, category} when method == "tools/call" -> {:error, {:not_dispatched, category}}
      error -> error
    end
  end

  # Each step is tagged so a failure logs which check refused, while callers
  # keep seeing the one category they always did.
  defp prepare(state) do
    with {:credentials, {:ok, %{url: url, access_token: token} = credentials}} <-
           {:credentials, MCPServers.credentials(state.user, state.id)},
         {:token, true} <-
           {:token, is_binary(token) and byte_size(token) in 1..65_536 and Regex.match?(~r/\A[\x21-\x7E]+\z/, token)},
         {:endpoint, true} <- {:endpoint, fingerprint(url) == state.endpoint},
         {:https, {:ok, _}} <- {:https, OAuth.https_uri(url)},
         {:pin, {:ok, pinned, host}} <- {:pin, SSRFGuard.pin(url)},
         {:authorized, true} <- {:authorized, state.authorized?.()} do
      {:ok, credentials, pinned, host}
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

  defp dispatch(state, credentials, pinned, host, envelope, notification) do
    max_body = if envelope.method == "tools/list", do: @catalog_limit, else: @body_limit

    headers = [
      {"authorization", "Bearer " <> credentials.access_token},
      {"content-type", "application/json"},
      {"accept", "application/json, text/event-stream"},
      {"mcp-protocol-version", state.version}
    ]

    headers = if state.session, do: [{"mcp-session-id", state.session} | headers], else: headers

    with {:ok, response} <-
           PinnedHTTP.request("POST", pinned,
             headers: headers,
             body: JSON.encode!(envelope),
             connect_options: SSRFGuard.connect_options(host) ++ [timeout: 5_000],
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
      {:ok, redact(result, credentials.access_token), %{state | session: session, next_id: state.next_id + 1}}
    else
      {:error, :mcp_tool_failed} = error ->
        error

      failure ->
        log_failure(state, "#{envelope.method} #{describe(failure)}")
        {:error, :mcp_unavailable}
    end
  rescue
    error ->
      log_failure(state, "#{envelope.method} raised #{inspect(error.__struct__)}")
      {:error, :mcp_unavailable}
  catch
    :exit, _ ->
      log_failure(state, "#{envelope.method} exited")
      {:error, :mcp_unavailable}
  end

  # Only the failure's category: error terms can hold URLs, headers or bodies.
  defp log_failure(state, reason), do: Logger.warning("MCP server #{state.id} of user #{state.user.id} failed: #{reason}")

  defp describe({:error, {:unexpected_status, status}}) when is_integer(status), do: "status #{status}"
  defp describe({:error, %{__struct__: module, reason: reason}}) when is_atom(reason), do: "#{inspect(module)} #{reason}"
  defp describe({:error, %{__struct__: module}}), do: inspect(module)
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
    if String.starts_with?(String.downcase(header(headers, "content-type") || ""), "text/event-stream") do
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
        if String.starts_with?(line, "event:"), do: String.trim(String.replace_prefix(line, "event:", ""))
      end)

    data =
      lines
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map_join("\n", &(&1 |> String.replace_prefix("data:", "") |> String.replace_prefix(" ", "")))

    if event in [nil, "", "message"] and data != "", do: [decode(data, id)], else: []
  end

  defp decode(body, id) do
    case JSON.decode(body) do
      {:ok, %{"jsonrpc" => "2.0", "id" => ^id, "result" => %{} = result} = envelope} ->
        if Map.has_key?(envelope, "error"), do: {:error, :mcp_invalid_response}, else: {:ok, result}

      {:ok, %{"jsonrpc" => "2.0", "id" => ^id, "error" => %{"code" => code, "message" => message}} = envelope}
      when is_integer(code) and is_binary(message) ->
        if Map.has_key?(envelope, "result"), do: {:error, :mcp_invalid_response}, else: {:error, :mcp_tool_failed}

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
        if Regex.match?(~r/\A[\x21-\x7E]+\z/, id), do: {:ok, id}, else: {:error, :mcp_invalid_response}

      _ ->
        {:error, :mcp_invalid_response}
    end
  end

  defp header(headers, key),
    do: Enum.find_value(headers, fn {name, value} -> if String.downcase(name) == key, do: value end)

  def valid_tool?(%{"name" => name, "inputSchema" => %{"type" => "object"} = schema} = tool)
      when is_binary(name) and byte_size(name) in 1..128 do
    Regex.match?(~r/\A[a-zA-Z0-9_.-]+\z/, name) and
      (is_nil(tool["description"]) or (is_binary(tool["description"]) and byte_size(tool["description"]) <= 4096)) and
      bounded?(schema, 12, 2000, 32_768) and safe_schema?(schema) and valid_schema?(schema)
  end

  def valid_tool?(_), do: false

  defp safe_schema?(map) when is_map(map),
    do:
      Enum.all?(map, fn {key, value} ->
        key not in ["$ref", "$dynamicRef", "$recursiveRef", "$schema", "$id"] and safe_schema?(value)
      end)

  defp safe_schema?(list) when is_list(list), do: Enum.all?(list, &safe_schema?/1)
  defp safe_schema?(_), do: true

  defp valid_schema?(schema) do
    ExJsonSchema.Schema.resolve(Map.put(schema, "$schema", "http://json-schema.org/draft-07/schema#"))
    true
  rescue
    _ -> false
  end

  defp bounded?(value, depth, nodes, bytes),
    do: tree_size(value, depth, nodes) >= 0 and byte_size(JSON.encode!(value)) <= bytes

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

  defp tree_size(value, _, nodes) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
    do: nodes - 1

  defp tree_size(_, _, _), do: -1
  defp redact(value, token) when is_binary(value), do: String.replace(value, token, "[REDACTED]")
  defp redact(value, token) when is_list(value), do: Enum.map(value, &redact(&1, token))

  defp redact(value, token) when is_map(value),
    do: Map.new(value, fn {key, item} -> {redact(key, token), redact(item, token)} end)

  defp redact(value, _), do: value
  defp tool_error(category), do: %{isError: true, content: [%{type: "text", text: Atom.to_string(category)}]}
end
