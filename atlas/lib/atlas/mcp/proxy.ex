defmodule Atlas.MCP.Proxy do
  @moduledoc """
  Client for configured upstream MCP servers.

  The first proxy transport is Streamable HTTP. Each operation opens a short
  upstream MCP session, performs the requested JSON-RPC call, and returns the
  upstream tool result through Atlas' authenticated MCP server.
  """

  alias Atlas.MCP, as: MCPContext
  alias Atlas.MCP.Proxy.Config
  alias Atlas.MCP.Proxy.Server

  require Logger

  @protocol_version "2025-03-26"
  @client_info %{"name" => "atlas-mcp-proxy", "version" => "0.1.0"}
  # The Tuist server's tools read production customer data, so they sit in the
  # same "observability" ("Production systems") group as the Grafana, Sentry and
  # Tuist database tools — granted by the same identity toggle.
  @server_tool_groups %{
    "grafana" => "observability",
    "sentry" => "observability",
    "tuist" => "observability"
  }

  def list_servers(config \\ proxy_config()) do
    config
    |> configured_servers()
    |> Enum.map(&public_server/1)
  end

  def configured_servers(config \\ proxy_config()) do
    config
    |> get_config(:servers, [])
    |> Enum.map(&normalize_server/1)
    |> Enum.reject(&is_nil/1)
  end

  def list_tools(server_name) when is_binary(server_name) do
    with {:ok, server} <- fetch_server(server_name),
         {:ok, tools} <- fetch_tools(server, nil) do
      {:ok, Enum.map(tools, &decorate_tool(server, &1))}
    end
  end

  def list_hoisted_tools(conn, config \\ proxy_config()) do
    config
    |> configured_servers()
    |> Enum.filter(&server_allowed?(conn, &1))
    |> Enum.flat_map(fn server ->
      case fetch_tools(server, conn) do
        {:ok, tools} ->
          Enum.map(tools, &hoist_tool(server, &1))

        {:error, message} ->
          Logger.warning("Skipping MCP proxy tools from #{server.name}: #{message}")
          []
      end
    end)
  end

  def call_tool(server_name, tool_name, arguments)
      when is_binary(server_name) and is_binary(tool_name) and is_map(arguments) do
    with {:ok, server} <- fetch_server(server_name) do
      dispatch_tool(server, nil, tool_name, arguments)
    end
  end

  def call_tool(_server_name, _tool_name, _arguments) do
    {:error, "Proxy tool calls require a string server name, string tool name, and map arguments."}
  end

  def call_hoisted_tool(conn, hoisted_name, arguments) when is_binary(hoisted_name) and is_map(arguments) do
    case resolve_hoisted_tool_name(hoisted_name) do
      {:ok, %Server{} = server, tool_name} ->
        if server_allowed?(conn, server) do
          dispatch_tool(server, conn, tool_name, arguments)
        else
          {:error, "Proxy tool #{hoisted_name} is not available for this MCP session."}
        end

      :error ->
        :not_proxy_tool
    end
  end

  def call_hoisted_tool(_conn, _hoisted_name, _arguments), do: :not_proxy_tool

  def fetch_server(name) when is_binary(name) do
    proxy_config()
    |> configured_servers()
    |> Enum.find(&(&1.name == name))
    |> case do
      nil -> {:error, "MCP proxy server is not configured: #{name}"}
      %Server{} = server -> {:ok, server}
    end
  end

  defp proxy_config, do: Config.get()

  defp server_allowed?(conn, %Server{} = server) do
    not restricted_mcp_session?(conn) or server_tool_group(server) in allowed_tool_groups(conn)
  end

  defp server_tool_group(%Server{name: name}), do: Map.get(@server_tool_groups, name, "default")

  defp restricted_mcp_session?(%{assigns: %{mcp_claims: %{"mcp_tool_groups" => groups}}}) when is_list(groups), do: true

  defp restricted_mcp_session?(_conn), do: false

  defp allowed_tool_groups(%{assigns: %{mcp_claims: %{"mcp_tool_groups" => groups}}}) when is_list(groups) do
    ["default" | Enum.map(groups, &to_string/1)]
  end

  defp allowed_tool_groups(_conn), do: ["default"]

  defp normalize_server(raw) do
    name = get_config(raw, :name)
    url = get_config(raw, :url)
    transport = normalize_transport(get_config(raw, :transport, :streamable_http))
    bearer_token = get_config(raw, :bearer_token)
    auth_type = normalize_auth_type(raw, bearer_token)

    cond do
      not present?(name) or not present?(url) ->
        nil

      transport != :streamable_http ->
        nil

      true ->
        %Server{
          name: name,
          url: url,
          auth_type: auth_type,
          authorization_url: get_config(raw, :authorization_url),
          token_url: get_config(raw, :token_url),
          registration_url: get_config(raw, :registration_url),
          client_id: get_config(raw, :client_id),
          client_secret: get_config(raw, :client_secret),
          scopes: normalize_scopes(get_config(raw, :scopes, [])),
          authorization_params: normalize_map(get_config(raw, :authorization_params, %{})),
          token_headers: normalize_headers(get_config(raw, :token_headers, [])),
          shared_oauth: truthy?(get_config(raw, :shared_oauth, false)),
          shared_oauth_user_email: get_config(raw, :shared_oauth_user_email),
          transport: transport,
          headers: normalize_headers(get_config(raw, :headers, [])),
          read_only: truthy?(get_config(raw, :read_only, false)),
          tool_allowlist: normalize_scopes(get_config(raw, :tool_allowlist, [])),
          operator_grant_header: get_config(raw, :operator_grant_header),
          bearer_token: bearer_token,
          receive_timeout: normalize_timeout(get_config(raw, :receive_timeout, 15_000))
        }
    end
  end

  defp normalize_auth_type(raw, bearer_token) do
    auth_type =
      raw
      |> get_config(:auth_type, get_config(raw, :auth))
      |> explicit_auth_type()

    auth_type || infer_auth_type(raw, bearer_token)
  end

  defp explicit_auth_type("oauth2"), do: :oauth2
  defp explicit_auth_type(:oauth2), do: :oauth2
  defp explicit_auth_type("bearer_token"), do: :bearer_token
  defp explicit_auth_type(:bearer_token), do: :bearer_token
  defp explicit_auth_type("none"), do: :none
  defp explicit_auth_type(:none), do: :none
  defp explicit_auth_type(_auth_type), do: nil

  defp infer_auth_type(_raw, bearer_token) when is_binary(bearer_token) and bearer_token != "", do: :bearer_token

  defp infer_auth_type(raw, _bearer_token),
    do: if(present?(get_config(raw, :authorization_url)), do: :oauth2, else: :none)

  defp normalize_transport(:streamable_http), do: :streamable_http
  defp normalize_transport("streamable_http"), do: :streamable_http
  defp normalize_transport("streamable-http"), do: :streamable_http
  defp normalize_transport(_other), do: :unsupported

  defp normalize_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.flat_map(headers, fn
      {key, value} -> [{to_string(key), to_string(value)}]
      [key, value] -> [{to_string(key), to_string(value)}]
      %{"name" => key, "value" => value} -> [{to_string(key), to_string(value)}]
      %{name: key, value: value} -> [{to_string(key), to_string(value)}]
      _other -> []
    end)
  end

  defp normalize_headers(_headers), do: []

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp normalize_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)
  defp normalize_scopes(scopes) when is_binary(scopes), do: String.split(scopes, " ", trim: true)
  defp normalize_scopes(_scopes), do: []

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout

  defp normalize_timeout(timeout) when is_binary(timeout) do
    case Integer.parse(timeout) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> 15_000
    end
  end

  defp normalize_timeout(_timeout), do: 15_000

  defp public_server(%Server{} = server) do
    %{
      name: server.name,
      auth_type: Atom.to_string(server.auth_type),
      transport: "streamable_http",
      url: server.url
    }
  end

  defp fetch_tools(%Server{} = server, conn) do
    with_session(server, conn, &fetch_tools(server, conn, &1))
  end

  defp fetch_tools(%Server{} = server, conn, session_id) do
    case rpc_request(server, conn, session_id, "tools/list", %{}) do
      {:ok, %{"tools" => tools}} when is_list(tools) ->
        {:ok, permitted_tools(server, tools)}

      {:ok, _other} ->
        {:error, "Upstream MCP server did not return a tools list."}

      {:error, _message} = error ->
        error
    end
  end

  # One session for both calls. The permission check reads `tools/list` from the
  # upstream, and reusing the session the call itself needs turns six POSTs and
  # two sessions into four and one — the guard only runs for restricted
  # upstreams, so it was the artifact-heavy path paying for it.
  defp dispatch_tool(%Server{} = server, conn, tool_name, arguments) do
    server
    |> with_session(conn, fn session_id ->
      with :ok <- ensure_tool_permitted(server, conn, session_id, tool_name) do
        rpc_request(server, conn, session_id, "tools/call", %{
          "name" => tool_name,
          "arguments" => arguments
        })
      end
    end)
    |> offer_operator_grant(server, conn)
  end

  # A refusal nobody can act on is a dead end. The upstream knows which account
  # owns the record and says so; the operator knows why they are looking. This
  # is the only place both are in hand, so it is where the refusal becomes the
  # request that would lift it.
  #
  # Only when the user holds no usable grant — someone whose grant is for
  # another account, or whose call failed for an unrelated reason, is told
  # nothing new.
  defp offer_operator_grant({:ok, %{"isError" => true} = result}, %Server{operator_grant_header: header} = server, %{
         assigns: %{current_user: user}
       })
       when is_binary(header) do
    with {:ok, account_handle} <- refused_account(result),
         true <- offer_needed?(user, server.name, account_handle),
         {:ok, offer} <- MCPContext.start_operator_grant_request(user, server.name, account_handle) do
      {:ok,
       result
       |> append_text(grant_offer(account_handle, offer.url))
       |> put_grant_meta(server, account_handle, offer)}
    else
      _ -> {:ok, result}
    end
  end

  defp offer_operator_grant(result, _server, _conn), do: result

  # Holding a grant is not the same as holding the right one. Grants name a
  # single account, so an operator part-way through a shift that touches two
  # customers has a live grant and still cannot read the second — asking
  # whether one exists at all would leave exactly that person at the dead end
  # this offer removes. One grant per user per server already treats moving
  # accounts as a replacement, so offering here matches what storing it does.
  defp offer_needed?(user, server_name, refused_handle) do
    case MCPContext.proxyable_operator_grant(user, server_name) do
      nil -> true
      %{account_handle: held} -> String.downcase(held) != String.downcase(refused_handle)
    end
  end

  # The wording is the upstream's, pinned by a test on its side. Failing to
  # match costs the link, not the refusal.
  @refused_account ~r/It belongs to the account "([a-zA-Z0-9-]+)"\./

  defp refused_account(%{"content" => content}) when is_list(content) do
    content
    |> Enum.find_value(fn
      %{"type" => "text", "text" => text} when is_binary(text) ->
        case Regex.run(@refused_account, text) do
          [_full, handle] -> handle
          _ -> nil
        end

      _ ->
        nil
    end)
    |> case do
      nil -> :error
      handle -> {:ok, handle}
    end
  end

  defp refused_account(_result), do: :error

  defp append_text(%{"content" => content} = result, text) when is_list(content) do
    %{result | "content" => content ++ [%{"type" => "text", "text" => text}]}
  end

  defp append_text(result, _text), do: result

  # The account is stated rather than assumed: this text is reached by way of
  # customer data, so the handle is named for a person to check before they
  # justify anything.
  defp grant_offer(account_handle, url) do
    "No operator grant for #{account_handle} is stored for this session. " <>
      "To investigate this account, open #{url} and state why access is needed. " <>
      "The grant is stored on return and this call will then succeed. " <>
      "Confirm the account named on that form is the customer you mean to look at."
  end

  # The sentence above addresses whoever reads the transcript; this addresses
  # whatever renders it. Relaying a link is left to a model noticing prose,
  # which is the part of this hand-off that fails quietly, so the same offer
  # goes out in a shape a client can act on: show the round trip as an
  # affordance, then retry the call the person was already making.
  #
  # `_meta` is the specification's extension point and unknown keys are ignored,
  # so a client that does not read this is no worse off than before. The prose
  # therefore stays rather than being replaced by it.
  #
  # This stands in for `URLElicitationRequiredError` (-32042), which the
  # 2025-11-25 revision added for this exact hand-off: a `url` to send someone
  # to, an `elicitationId` tying the return to the request that caused it, and a
  # `notifications/elicitation/complete` telling the client the out-of-band step
  # finished. `requestUrl` and `state` below are the first two under other
  # names; nothing here replaces the third, so a client still learns the grant
  # landed by retrying. Atlas negotiates 2025-06-18 and emcp implements neither
  # elicitation nor any server-to-client message, so this cannot be sent yet.
  # When it can, this function is a deletion rather than a migration.
  #
  # Step-up authorization (SEP-835) is the wrong tool for this and worth not
  # reaching for: it challenges the scopes of the client's own token at this
  # server, whereas what is missing here is Atlas' credential to an upstream.
  @grant_meta_key "atlas/operatorGrant"
  @grant_required_code "operator_grant_required"

  defp put_grant_meta(result, %Server{} = server, account_handle, offer) do
    grant = %{
      "code" => @grant_required_code,
      "server" => server.name,
      "account" => account_handle,
      "requestUrl" => offer.url,
      "state" => offer.state,
      "expiresAt" => DateTime.to_iso8601(offer.expires_at),
      # Nothing about the call was wrong, only the credential behind it, so the
      # same arguments succeed once the grant is stored. A client that retries
      # on its own needs to be told that much.
      "retryable" => true
    }

    Map.put(result, "_meta", Map.put(result["_meta"] || %{}, @grant_meta_key, grant))
  end

  # Two independent filters, both fail-closed.
  #
  # `readOnlyHint` is the upstream's own claim about a tool, and a tool with no
  # annotation is dropped rather than assumed safe. That claim is only worth
  # acting on where the upstream cannot make it by accident: Tuist requires each
  # tool to declare the hint, so a write tool that says nothing fails to compile
  # rather than arriving here wearing a read-only label.
  #
  # The allowlist stays for upstreams that offer no such guarantee — naming the
  # tools outright is the fallback when an annotation cannot be trusted. It costs
  # a deploy per new tool, so prefer it only where that is the honest trade.
  defp permitted_tools(%Server{} = server, tools) do
    tools
    |> filter_read_only(server)
    |> filter_allowlisted(server)
  end

  defp filter_read_only(tools, %Server{read_only: true}), do: Enum.filter(tools, &read_only_tool?/1)
  defp filter_read_only(tools, %Server{}), do: tools

  defp filter_allowlisted(tools, %Server{tool_allowlist: []}), do: tools

  defp filter_allowlisted(tools, %Server{tool_allowlist: allowed}), do: Enum.filter(tools, &(&1["name"] in allowed))

  defp read_only_tool?(%{"annotations" => %{"readOnlyHint" => true}}), do: true
  defp read_only_tool?(_tool), do: false

  # Discovery filtering alone would only hide the tools; a caller that already
  # knows a name could still dispatch to it. `fetch_tools/2` has applied the
  # same filter, so membership in its result is the authorization.
  defp ensure_tool_permitted(%Server{read_only: false, tool_allowlist: []}, _conn, _session_id, _tool_name), do: :ok

  defp ensure_tool_permitted(%Server{} = server, conn, session_id, tool_name) do
    with {:ok, tools} <- fetch_tools(server, conn, session_id) do
      if Enum.any?(tools, &(&1["name"] == tool_name)) do
        :ok
      else
        {:error, "Proxy tool #{tool_name} is not available: #{server.name} is proxied with a restricted tool set."}
      end
    end
  end

  defp decorate_tool(%Server{} = server, tool) when is_map(tool) do
    tool
    |> Map.put("server", server.name)
    |> Map.put("proxiedName", "#{server.name}/#{tool["name"]}")
  end

  defp hoist_tool(%Server{} = server, %{"name" => tool_name} = tool) when is_binary(tool_name) do
    original_description = tool["description"] || "Upstream MCP tool."
    description = "[#{server.name}] #{original_description}"

    tool
    |> Map.put("name", hoisted_tool_name(server.name, tool_name))
    |> Map.put("description", description)
    |> Map.put(
      "_meta",
      Map.merge(tool["_meta"] || %{}, %{
        "atlas/proxyServer" => server.name,
        "atlas/originalToolName" => tool_name
      })
    )
  end

  defp resolve_hoisted_tool_name(name) do
    case String.split(name, "__", parts: 2) do
      [server_name, tool_name] when server_name != "" and tool_name != "" ->
        case fetch_server(server_name) do
          {:ok, %Server{} = server} -> {:ok, server, tool_name}
          {:error, _message} -> :error
        end

      _ ->
        :error
    end
  end

  defp hoisted_tool_name(server_name, tool_name), do: "#{server_name}__#{tool_name}"

  defp with_session(%Server{} = server, conn, callback) do
    with {:ok, session_id} <- initialize(server, conn),
         :ok <- send_initialized(server, conn, session_id) do
      callback.(session_id)
    end
  end

  defp initialize(%Server{} = server, conn) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => request_id(),
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => @protocol_version,
        "capabilities" => %{},
        "clientInfo" => @client_info
      }
    }

    with {:ok, body, session_id} <- post_json(server, request, nil, conn),
         {:ok, _result} <- rpc_result(server, body) do
      require_session_id(server, session_id)
    end
  end

  defp send_initialized(%Server{} = server, conn, session_id) do
    request = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}

    case post_json(server, request, session_id, conn) do
      {:ok, _body, _session_id} -> :ok
      {:error, _message} = error -> error
    end
  end

  defp rpc_request(%Server{} = server, conn, session_id, method, params) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => request_id(),
      "method" => method,
      "params" => params
    }

    with {:ok, body, _session_id} <- post_json(server, request, session_id, conn) do
      rpc_result(server, body)
    end
  end

  defp post_json(%Server{} = server, payload, session_id, conn) do
    with {:ok, request} <- request(server, conn, session_id) do
      request =
        request
        |> Req.merge(json: payload)
        |> Req.merge(into: stream_response(payload))

      case Req.post(request) do
        {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
          {:ok, decode_response_body(response.body, payload), response_session_id(response)}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.warning("MCP proxy #{server.name} HTTP error: status=#{status} body=#{inspect(body)}")
          {:error, "Upstream MCP server #{server.name} returned HTTP #{status}."}

        {:error, reason} ->
          Logger.warning("MCP proxy #{server.name} transport error: #{inspect(reason)}")
          {:error, "Could not reach upstream MCP server #{server.name}: #{inspect(reason)}"}
      end
    end
  end

  defp request(%Server{} = server, conn, session_id) do
    headers =
      server.headers
      |> put_default_header("accept", "application/json, text/event-stream")
      |> put_default_header("mcp-protocol-version", @protocol_version)
      |> maybe_put_header("mcp-session-id", session_id)
      |> maybe_put_header(server.operator_grant_header, operator_grant_token(server, conn))

    with {:ok, auth_token} <- auth_token(server, conn) do
      request = Req.new(url: server.url, headers: headers, receive_timeout: server.receive_timeout)
      {:ok, maybe_put_auth(request, auth_token)}
    end
  end

  # An operator grant elevates the upstream session beyond the user's own
  # memberships, so it travels per user and per request — never from static
  # config, which every session would share. Its absence is not an error: most
  # requests are for data the user can already read, and the upstream refuses
  # anything else on its own.
  #
  # Only a read-tier grant is forwarded, so what the upstream will do for this
  # request is bounded by the credential rather than by which tools this proxy
  # happens to expose. Dropping an admin grant degrades the request to the
  # user's own memberships, which is the direction worth failing in.
  defp operator_grant_token(%Server{operator_grant_header: nil}, _conn), do: nil

  defp operator_grant_token(%Server{} = server, %{assigns: %{current_user: user}}) do
    case MCPContext.proxyable_operator_grant(user, server.name) do
      %{token: token} -> token
      nil -> nil
    end
  end

  defp operator_grant_token(_server, _conn), do: nil

  defp auth_token(%Server{auth_type: :bearer_token, bearer_token: token}, _conn), do: {:ok, token}
  defp auth_token(%Server{auth_type: :none}, _conn), do: {:ok, nil}

  defp auth_token(%Server{auth_type: :oauth2} = server, %{assigns: %{current_user: user}}) do
    case MCPContext.access_token_for(user, server) do
      {:ok, token} ->
        {:ok, token}

      {:error, :authorization_required} ->
        {:error, "MCP server #{server.name} needs authorization. Open /admin/mcps to connect it."}

      {:error, {:refresh_failed, _reason}} ->
        {:error, "MCP server #{server.name} needs authorization. Open /admin/mcps to reconnect it."}

      {:error, reason} ->
        {:error, "MCP server #{server.name} authorization failed: #{inspect(reason)}"}
    end
  end

  defp auth_token(%Server{auth_type: :oauth2} = server, _conn) do
    {:error, "MCP server #{server.name} needs an authenticated Atlas user session."}
  end

  defp maybe_put_auth(request, token) when is_binary(token) and token != "" do
    Req.merge(request, auth: {:bearer, token})
  end

  defp maybe_put_auth(request, _token), do: request

  defp stream_response(payload) do
    fn {:data, data}, {request, response} ->
      body = response.body <> data

      if sse_response?(response) do
        case decode_response_body(body, payload) do
          %{} = message -> {:halt, {request, %{response | body: message}}}
          _other -> {:cont, {request, %{response | body: body}}}
        end
      else
        {:cont, {request, %{response | body: body}}}
      end
    end
  end

  defp sse_response?(%Req.Response{headers: headers}) do
    headers
    |> get_header("content-type")
    |> first_header_value()
    |> case do
      content_type when is_binary(content_type) ->
        String.starts_with?(String.downcase(content_type), "text/event-stream")

      _other ->
        false
    end
  end

  defp put_default_header(headers, key, value) do
    if Enum.any?(headers, fn {header_key, _header_value} -> String.downcase(header_key) == key end) do
      headers
    else
      [{key, value} | headers]
    end
  end

  defp maybe_put_header(headers, _key, nil), do: headers
  defp maybe_put_header(headers, _key, ""), do: headers
  defp maybe_put_header(headers, key, value), do: [{key, value} | headers]

  defp rpc_result(%Server{}, %{"result" => result}), do: {:ok, result}

  defp rpc_result(%Server{} = server, %{"error" => %{"message" => message}}) do
    {:error, "Upstream MCP server #{server.name} returned an error: #{message}"}
  end

  defp rpc_result(%Server{} = server, %{"error" => error}) do
    {:error, "Upstream MCP server #{server.name} returned an error: #{inspect(error)}"}
  end

  defp rpc_result(%Server{} = server, body) do
    {:error, "Upstream MCP server #{server.name} returned an invalid JSON-RPC response: #{inspect(body)}"}
  end

  defp decode_response_body(body, payload) when is_binary(body) do
    with {:ok, messages} <- decode_sse_messages(body),
         %{} = message <- matching_message(messages, payload) do
      message
    else
      _other ->
        case JSON.decode(body) do
          {:ok, decoded} -> decoded
          {:error, _reason} -> body
        end
    end
  end

  defp decode_response_body(body, _payload), do: body

  defp decode_sse_messages(body) do
    messages =
      body
      |> String.split(~r/\r?\n\r?\n/, trim: true)
      |> Enum.flat_map(&decode_sse_message/1)

    if messages == [], do: :error, else: {:ok, messages}
  end

  defp decode_sse_message(event) do
    event
    |> String.split(~r/\r?\n/)
    |> Enum.flat_map(fn
      "data: " <> data -> [data]
      "data:" <> data -> [String.trim_leading(data)]
      _line -> []
    end)
    |> case do
      [] ->
        []

      data_lines ->
        data_lines
        |> Enum.join("\n")
        |> JSON.decode()
        |> case do
          {:ok, message} -> [message]
          {:error, _reason} -> []
        end
    end
  end

  defp matching_message(messages, %{"id" => id}) do
    Enum.find(messages, fn
      %{"id" => ^id} -> true
      _message -> false
    end) || Enum.find(messages, &json_rpc_response?/1)
  end

  defp matching_message(messages, _payload), do: Enum.find(messages, &json_rpc_response?/1)

  defp json_rpc_response?(%{"result" => _result}), do: true
  defp json_rpc_response?(%{"error" => _error}), do: true
  defp json_rpc_response?(_message), do: false

  defp require_session_id(%Server{}, session_id) when is_binary(session_id) and session_id != "" do
    {:ok, session_id}
  end

  defp require_session_id(%Server{} = server, _session_id) do
    {:error, "Upstream MCP server #{server.name} did not return an MCP session ID."}
  end

  defp response_session_id(%Req.Response{headers: headers}) when is_map(headers) do
    headers |> get_header("mcp-session-id") |> first_header_value()
  end

  defp response_session_id(%Req.Response{headers: headers}) when is_list(headers) do
    headers
    |> Enum.find_value(fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == "mcp-session-id", do: value

      _other ->
        nil
    end)
    |> first_header_value()
  end

  defp response_session_id(_response), do: nil

  defp get_header(headers, key) do
    Map.get(headers, key) || Map.get(headers, String.downcase(key)) || Map.get(headers, String.upcase(key)) || []
  end

  defp first_header_value([value | _rest]), do: value
  defp first_header_value(value) when is_binary(value), do: value
  defp first_header_value(_value), do: nil

  defp request_id, do: System.unique_integer([:positive])

  defp get_config(config, key, default \\ nil)

  defp get_config(config, key, default) when is_list(config) do
    keyword_value =
      if Keyword.keyword?(config) do
        Keyword.get(config, key)
      end

    keyword_value || list_config_value(config, key) || default
  end

  defp get_config(config, key, default) when is_map(config) do
    Map.get(config, key) || Map.get(config, to_string(key)) || default
  end

  defp get_config(_config, _key, default), do: default

  defp list_config_value(config, key) do
    string_key = to_string(key)

    Enum.find_value(config, fn
      {^key, value} -> value
      {^string_key, value} -> value
      _other -> nil
    end)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_value), do: false
end
