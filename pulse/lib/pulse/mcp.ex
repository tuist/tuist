defmodule Pulse.MCP do
  @moduledoc """
  Stateless Model Context Protocol server surface, revision `2026-07-28`.

  Every request carries its protocol version and client capabilities in
  `params._meta`, so the server keeps no handshake or session state and
  answers each request independently. Supported methods are
  `server/discover`, `tools/list`, `tools/call`, and `subscriptions/listen`.
  The legacy `initialize` handshake and `ping` were removed by this revision
  and return method-not-found.

  Query tools are read-only; alert-management tools require separately configured
  capability-scoped principals. Infrastructure remediation lives in a separate
  server, not this registry (see `docs/architecture.md`).

  This module is transport-agnostic. HTTP concerns (status codes, mirrored
  request headers, and origin checks) live in `PulseWeb.MCPController`.
  """

  alias Pulse.Alerting.{Resources, Subscriptions}
  alias Pulse.MCP.Tools
  alias Pulse.QueryLimit

  @protocol_version "2026-07-28"
  @supported_versions [@protocol_version]

  @meta_protocol_version "io.modelcontextprotocol/protocolVersion"
  @meta_client_capabilities "io.modelcontextprotocol/clientCapabilities"
  @meta_client_info "io.modelcontextprotocol/clientInfo"
  @meta_server_info "io.modelcontextprotocol/serverInfo"
  @meta_subscription_id "io.modelcontextprotocol/subscriptionId"

  @list_ttl_ms 60_000
  @cache_scope "private"

  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @unsupported_protocol_version -32_022

  @subscription_flags ["toolsListChanged", "promptsListChanged", "resourcesListChanged"]

  @type context :: %{optional(:conn) => Plug.Conn.t()}
  @type id :: String.t() | integer()
  @type message ::
          {:request, id(), String.t(), map()}
          | {:notification, String.t()}
          | {:invalid, id() | nil}

  @doc "Protocol versions this server implements."
  @spec supported_versions() :: [String.t()]
  def supported_versions, do: @supported_versions

  @doc """
  Classify a decoded JSON-RPC message without executing it.

  Requests have a string or integer `id`; notifications have no `id` key.
  Anything else, including batches, responses, a `null` identifier, or
  non-object `params`, is invalid.
  """
  @spec classify(term()) :: message()
  def classify(%{"jsonrpc" => "2.0", "method" => method} = msg) when is_binary(method) do
    cond do
      Map.has_key?(msg, "params") and not is_map(msg["params"]) -> {:invalid, readable_id(msg)}
      not Map.has_key?(msg, "id") -> {:notification, method}
      valid_id?(msg["id"]) -> {:request, msg["id"], method, Map.get(msg, "params", %{})}
      true -> {:invalid, nil}
    end
  end

  def classify(msg), do: {:invalid, readable_id(msg)}

  @doc """
  Dispatch a single JSON-RPC message.

  Returns `{:reply, response}` for requests, `{:stream, messages}` when the
  response is a sequence of messages ending in the final response (used by
  `subscriptions/listen`), and `:noreply` for notifications. Notifications
  are never executed: this revision defines no client-to-server
  notification over HTTP.
  """
  @spec dispatch(term(), context()) :: {:reply, map()} | {:stream, [map()]} | :noreply
  def dispatch(msg, context \\ %{}) do
    case classify(msg) do
      {:notification, _method} ->
        :noreply

      {:invalid, id} ->
        {:reply, error_response(id, @invalid_request, "Invalid Request")}

      {:request, id, method, params} ->
        with :ok <- validate_meta(params),
             :ok <- validate_version(params),
             {:ok, result} <- handle(method, params, id, context) do
          {:reply, %{"jsonrpc" => "2.0", "id" => id, "result" => complete(result)}}
        else
          {:stream, messages} -> {:stream, messages}
          {:subscription, subscription} -> {:subscription, subscription}
          {:error, code, message, data} -> {:reply, error_response(id, code, message, data)}
        end
    end
  end

  @doc "Build a JSON-RPC error response, omitting an unreadable identifier."
  @spec error_response(id() | nil, integer(), String.t(), term()) :: map()
  def error_response(id, code, message, data \\ nil) do
    error = %{"code" => code, "message" => message}
    error = if is_nil(data), do: error, else: Map.put(error, "data", data)
    response = %{"jsonrpc" => "2.0", "error" => error}
    if is_nil(id), do: response, else: Map.put(response, "id", id)
  end

  defp validate_meta(%{"_meta" => meta}) when is_map(meta) do
    cond do
      not is_binary(meta[@meta_protocol_version]) ->
        invalid_params("_meta.#{@meta_protocol_version} must be a string")

      not is_map(meta[@meta_client_capabilities]) ->
        invalid_params("_meta.#{@meta_client_capabilities} must be an object")

      Map.has_key?(meta, @meta_client_info) and not implementation?(meta[@meta_client_info]) ->
        invalid_params("_meta.#{@meta_client_info} must have string name and version")

      true ->
        :ok
    end
  end

  defp validate_meta(_params), do: invalid_params("params._meta is required")

  defp validate_version(%{"_meta" => %{@meta_protocol_version => version}}) do
    if version in @supported_versions do
      :ok
    else
      {:error, @unsupported_protocol_version, "Unsupported protocol version",
       %{"supported" => @supported_versions, "requested" => version}}
    end
  end

  defp implementation?(%{"name" => name, "version" => version}), do: is_binary(name) and is_binary(version)
  defp implementation?(_), do: false

  defp handle("server/discover", _params, _id, _context) do
    {:ok,
     %{
       "supportedVersions" => @supported_versions,
       "capabilities" => capabilities(),
       "ttlMs" => @list_ttl_ms,
       "cacheScope" => @cache_scope
     }}
  end

  defp handle("tools/list", _params, _id, _context) do
    {:ok, %{"tools" => Tools.list(), "ttlMs" => @list_ttl_ms, "cacheScope" => @cache_scope}}
  end

  defp handle("tools/call", %{"name" => name} = params, _id, context) when is_binary(name) do
    arguments = Map.get(params, "arguments", %{})

    cond do
      not is_map(arguments) ->
        invalid_params("params.arguments must be an object")

      not Tools.known?(name) ->
        invalid_params("Unknown tool: #{name}")

      true ->
        case Tools.call(name, arguments, context) do
          {:ok, content} ->
            {:ok, %{"content" => content, "isError" => false}}

          {:error, reason} ->
            {:ok, %{"content" => [%{"type" => "text", "text" => error_text(name, reason)}], "isError" => true}}
        end
    end
  end

  defp handle("tools/call", _params, _id, _context), do: invalid_params("params.name must be a string")

  defp handle("resources/list", params, _id, %{conn: conn}), do: resource_result(Resources.list(conn, params))
  defp handle("resources/read", %{"uri" => uri}, _id, %{conn: conn}), do: resource_result(Resources.read(conn, uri))

  defp handle("resources/templates/list", _params, _id, _context),
    do: {:ok, %{"resourceTemplates" => Resources.templates(), "ttlMs" => @list_ttl_ms, "cacheScope" => @cache_scope}}

  defp handle(method, _params, _id, _context) when method in ["resources/list", "resources/read"],
    do: invalid_params("Resource requests need a valid URI and authenticated HTTP context")

  defp handle("subscriptions/listen", params, id, context) do
    with :ok <- validate_subscription_filter(params["notifications"]) do
      requested = Map.get(params["notifications"], "resourceSubscriptions", [])
      resources = Enum.filter(requested, &match?({:ok, _, _, _}, Resources.parse(&1)))
      subscription(resources, id, context)
    end
  end

  defp handle("initialize", _params, _id, _context) do
    {:error, @method_not_found, "Method not found: initialize was removed in protocol #{@protocol_version}",
     %{"supported" => @supported_versions}}
  end

  defp handle(method, _params, _id, _context), do: {:error, @method_not_found, "Method not found: #{method}", nil}

  defp subscription([], id, _context) do
    {ack, completion} = subscription_messages(id, %{})
    {:stream, [ack, completion]}
  end

  defp subscription(resources, id, %{conn: conn}) do
    case Subscriptions.prepare(conn, resources) do
      {:ok, descriptor} ->
        {ack, completion} = subscription_messages(id, %{"resourceSubscriptions" => descriptor.uris})
        {:subscription, %{descriptor: descriptor, acknowledgement: ack, completion: completion}}

      error ->
        resource_result(error)
    end
  end

  defp subscription(_, _, _), do: resource_result({:error, :unauthorized})

  defp subscription_messages(id, filter) do
    meta = Map.put(server_meta(), @meta_subscription_id, id)

    ack = %{
      "jsonrpc" => "2.0",
      "method" => "notifications/subscriptions/acknowledged",
      "params" => %{"_meta" => meta, "notifications" => filter}
    }

    completion = %{"jsonrpc" => "2.0", "id" => id, "result" => %{"resultType" => "complete", "_meta" => meta}}
    {ack, completion}
  end

  defp resource_result({:ok, result}), do: {:ok, result}
  defp resource_result({:error, :unauthorized}), do: {:error, -32_001, "Unauthorized", nil}
  defp resource_result({:error, :forbidden}), do: {:error, -32_003, "Forbidden", nil}

  defp resource_result({:error, reason})
       when reason in [:invalid_uri, :not_found, :reset_required, :invalid_subscription],
       do: invalid_params("Resource is unavailable or continuation requires reset")

  defp resource_result({:error, _}), do: {:error, -32_000, "Alert resource unavailable", nil}

  defp validate_subscription_filter(filter) when is_map(filter) do
    Enum.reduce_while(filter, :ok, fn
      {key, value}, :ok when key in @subscription_flags and not is_boolean(value) ->
        {:halt, invalid_params("params.notifications.#{key} must be a boolean")}

      {"resourceSubscriptions", value}, :ok ->
        if is_list(value) and length(value) <= 32 and Enum.all?(value, &(is_binary(&1) and byte_size(&1) <= 512)),
          do: {:cont, :ok},
          else: {:halt, invalid_params("params.notifications.resourceSubscriptions must be an array of strings")}

      _entry, :ok ->
        {:cont, :ok}
    end)
  end

  defp validate_subscription_filter(_filter), do: invalid_params("params.notifications must be an object")

  defp capabilities,
    do: %{"tools" => %{"listChanged" => false}, "resources" => %{"listChanged" => false, "subscribe" => true}}

  defp complete(result) do
    result
    |> Map.put("resultType", "complete")
    |> Map.update("_meta", server_meta(), &Map.merge(&1, server_meta()))
  end

  defp server_meta do
    %{@meta_server_info => %{"name" => "pulse", "version" => to_string(Application.spec(:pulse, :vsn))}}
  end

  defp invalid_params(message), do: {:error, @invalid_params, message, nil}

  defp valid_id?(id), do: is_binary(id) or is_integer(id)

  defp readable_id(%{"id" => id}) do
    if valid_id?(id), do: id
  end

  defp readable_id(_msg), do: nil

  # Keep the inspected reason first (clients match on it) and say which bound
  # fired and how to stay inside it. Budgets are fixed per request.
  @trace_hints %{
    {"query_traces", :query_resource_limit} =>
      "retained spans exceeded the 16 MiB candidate budget; request only the fields you need, " <>
        "pass a smaller limit, such as 500, or narrow start_ts_ns/end_ts_ns",
    {"query_traces", :query_sample_limit} => "more than 5,000 spans matched; pass a limit or narrow the time window",
    {"get_trace", :query_sample_limit} =>
      "the trace has more than 5,000 stored spans; use query_traces with trace_id, a time window and a limit",
    {"get_trace", :query_resource_limit} =>
      "the trace exceeds the 16 MiB assembly budget; use query_traces with trace_id, a time window and a limit",
    {"get_trace", :query_timeout} =>
      "assembling every stored span of this trace exceeded the query deadline; " <>
        "use query_traces with trace_id, a time window and a limit",
    {"get_trace", :query_scan_limit} =>
      "the trace spans more stored segments than one query may read; " <>
        "use query_traces with trace_id, a time window and a limit"
  }

  defp error_text(name, reason) do
    # Prefer the failing query's recorded limit over a generic native hint:
    # resource errors also include workers killed at their BEAM heap bound.
    detail =
      if reason in [:query_scan_limit, :query_execution_limit, :query_resource_limit, :query_timeout],
        do: QueryLimit.describe(QueryLimit.take())

    hints = Enum.reject([detail || Map.get(@trace_hints, {name, reason})], &is_nil/1)

    if hints == [], do: inspect(reason), else: "#{inspect(reason)}: #{Enum.join(hints, "; ")}"
  end
end
