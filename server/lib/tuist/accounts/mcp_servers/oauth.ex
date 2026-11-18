defmodule Tuist.Accounts.MCPServers.OAuth do
  @moduledoc """
  The OAuth client side of the MCP authorization specification, for remote
  MCP servers users add: protected resource metadata discovery (RFC 9728),
  authorization server metadata discovery (RFC 8414 and OpenID Connect),
  dynamic client registration (RFC 7591), the authorization code grant with
  PKCE `S256`, and resource indicators (RFC 8707).

  Every URL comes from the user or from metadata a third party controls, so
  each request is HTTPS only, resolved and pinned to a public address by
  `Tuist.OAuth2.SSRFGuard`, bounded, and never redirected or retried.
  Failures are reported as status-only reasons so provider bodies never reach
  logs or the UI.
  """

  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard

  @protocol_version "2025-06-18"
  @max_token_bytes 65_536
  @max_response_bytes 262_144
  @request_deadline_ms 15_000

  @doc """
  Discovers how to authorize against the MCP server at `url`. Probes the
  endpoint for its `WWW-Authenticate` challenge and falls back to the
  well-known protected resource metadata locations.
  """
  def discover(url) do
    with {:ok, endpoint} <- https_uri(url),
         {:ok, metadata_urls, challenge_scope} <- resource_metadata_urls(endpoint),
         {:ok, resource} <- first_ok(metadata_urls, &fetch_resource_metadata(&1, endpoint)),
         {:ok, issuer} <- authorization_server(resource),
         {:ok, server} <- fetch_authorization_server_metadata(issuer) do
      {:ok,
       Map.merge(server, %{
         resource: resource["resource"],
         scope: challenge_scope || scopes(resource["scopes_supported"])
       })}
    end
  end

  @doc "Registers Tuist as a public client of the authorization server."
  def register(%{registration_endpoint: endpoint} = discovery, redirect_uri) when is_binary(endpoint) do
    body =
      reject_nil(%{
        "client_name" => "Tuist",
        "redirect_uris" => [redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none",
        "scope" => discovery[:scope]
      })

    case request("POST", endpoint, json: body) do
      {:ok, %{"client_id" => client_id} = response} when is_binary(client_id) and byte_size(client_id) in 1..1024 ->
        {:ok, %{client_id: client_id, client_secret: string_or_nil(response["client_secret"])}}

      {:ok, _body} ->
        {:error, :invalid_provider_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def register(_discovery, _redirect_uri), do: {:error, :registration_not_supported}

  def authorization_url(server, state, code_verifier, redirect_uri) do
    query =
      reject_nil(%{
        "response_type" => "code",
        "client_id" => server.client_id,
        "redirect_uri" => redirect_uri,
        "state" => state,
        "code_challenge" => code_challenge(code_verifier),
        "code_challenge_method" => "S256",
        "resource" => server.resource,
        "scope" => server.scope
      })

    uri = URI.parse(server.authorization_endpoint)
    query = if uri.query, do: uri.query <> "&" <> URI.encode_query(query), else: URI.encode_query(query)
    URI.to_string(%{uri | query: query})
  end

  def exchange_code(server, code, code_verifier, redirect_uri) do
    token_request(server, %{
      "grant_type" => "authorization_code",
      "code" => code,
      "code_verifier" => code_verifier,
      "redirect_uri" => redirect_uri
    })
  end

  @doc "Refreshes the session. Servers that do not rotate refresh tokens keep the current one."
  def refresh(server) do
    with {:ok, tokens} <-
           token_request(server, %{"grant_type" => "refresh_token", "refresh_token" => server.refresh_token}) do
      {:ok, Map.update!(tokens, :refresh_token, &(&1 || server.refresh_token))}
    end
  end

  def code_verifier, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp code_challenge(verifier), do: :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

  defp token_request(server, form) do
    form =
      reject_nil(
        Map.merge(form, %{
          "client_id" => server.client_id,
          "client_secret" => server.client_secret,
          "resource" => server.resource
        })
      )

    with {:ok, body} <- request("POST", server.token_endpoint, form: form) do
      token_attrs(body)
    end
  end

  defp token_attrs(%{"access_token" => access} = body)
       when is_binary(access) and byte_size(access) in 1..@max_token_bytes do
    refresh = body["refresh_token"]

    cond do
      not (is_nil(body["token_type"]) or
               (is_binary(body["token_type"]) and String.downcase(body["token_type"]) == "bearer")) ->
        {:error, :invalid_provider_response}

      not is_nil(refresh) and not (is_binary(refresh) and byte_size(refresh) in 1..@max_token_bytes) ->
        {:error, :invalid_provider_response}

      true ->
        {:ok, %{access_token: access, refresh_token: refresh, expires_at: expires_at(body["expires_in"])}}
    end
  end

  defp token_attrs(_body), do: {:error, :invalid_provider_response}

  # Without `expires_in` the lifetime is unknown; the token is used until the
  # server rejects it.
  defp expires_at(seconds) when is_integer(seconds) and seconds in 1..31_536_000,
    do: DateTime.add(DateTime.utc_now(:second), seconds, :second)

  defp expires_at(_seconds), do: nil

  # The MCP authorization specification signals a protected server with a 401
  # whose challenge names its resource metadata. Servers that omit it publish
  # the metadata at the well-known locations derived from the endpoint.
  defp resource_metadata_urls(endpoint) do
    well_known = [
      origin(endpoint) <> "/.well-known/oauth-protected-resource" <> path(endpoint),
      origin(endpoint) <> "/.well-known/oauth-protected-resource"
    ]

    case probe(endpoint) do
      {:ok, 401, headers} ->
        challenge = headers |> Map.get("www-authenticate", []) |> Enum.join(", ")

        case Regex.run(~r/resource_metadata="([^"]+)"/, challenge) do
          [_, url] -> {:ok, Enum.uniq([url | well_known]), challenge_param(challenge, "scope")}
          nil -> {:ok, Enum.uniq(well_known), challenge_param(challenge, "scope")}
        end

      {:ok, _status, _headers} ->
        {:ok, Enum.uniq(well_known), nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp challenge_param(challenge, name) do
    case Regex.run(~r/(?:^|[\s,])#{name}="([^"]*)"/, challenge) do
      [_, value] when value != "" -> value
      _ -> nil
    end
  end

  defp fetch_resource_metadata(url, endpoint) do
    with {:ok, %{"resource" => resource, "authorization_servers" => [_ | _]} = metadata} when is_binary(resource) <-
           request("GET", url),
         {:ok, resource_uri} <- https_uri(resource),
         # The resource must be the server the user added, so a compromised
         # metadata document cannot bind the tokens to another origin.
         true <- origin(resource_uri) == origin(endpoint) do
      {:ok, metadata}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :oauth_not_supported}
    end
  end

  defp authorization_server(%{"authorization_servers" => [issuer | _]}) when is_binary(issuer) do
    with {:ok, _uri} <- https_uri(issuer), do: {:ok, issuer}
  end

  defp authorization_server(_metadata), do: {:error, :oauth_not_supported}

  defp fetch_authorization_server_metadata(issuer) do
    {:ok, issuer_uri} = https_uri(issuer)
    origin = origin(issuer_uri)

    urls =
      case path(issuer_uri) do
        "" ->
          [origin <> "/.well-known/oauth-authorization-server", origin <> "/.well-known/openid-configuration"]

        path ->
          [
            origin <> "/.well-known/oauth-authorization-server" <> path,
            origin <> "/.well-known/openid-configuration" <> path,
            origin <> path <> "/.well-known/openid-configuration"
          ]
      end

    first_ok(urls, &fetch_authorization_server(&1, issuer))
  end

  defp fetch_authorization_server(url, issuer) do
    with {:ok, %{} = metadata} <- request("GET", url),
         true <- String.trim_trailing(to_string(metadata["issuer"]), "/") == String.trim_trailing(issuer, "/"),
         # PKCE is mandatory; the specification forbids proceeding without S256.
         true <- "S256" in List.wrap(metadata["code_challenge_methods_supported"]),
         {:ok, issuer_uri} <- https_uri(issuer),
         true <- same_origin?(metadata["authorization_endpoint"], issuer_uri),
         true <- same_origin?(metadata["token_endpoint"], issuer_uri) do
      registration =
        if same_origin?(metadata["registration_endpoint"], issuer_uri), do: metadata["registration_endpoint"]

      {:ok,
       %{
         issuer: metadata["issuer"],
         authorization_endpoint: metadata["authorization_endpoint"],
         token_endpoint: metadata["token_endpoint"],
         registration_endpoint: registration
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :oauth_not_supported}
    end
  end

  # A malicious MCP server can name an authorization server whose metadata
  # points the browser at an honest provider's authorization endpoint while
  # keeping its own token endpoint (a mix-up attack): the honest provider's
  # code and the PKCE verifier would then be sent to the attacker. Requiring
  # every endpoint on the issuer's own origin rules that out.
  defp same_origin?(url, issuer_uri) do
    case https_uri(url) do
      {:ok, uri} -> origin(uri) == origin(issuer_uri)
      _ -> false
    end
  end

  defp first_ok(urls, fun) do
    Enum.reduce_while(urls, {:error, :oauth_not_supported}, fn url, _acc ->
      case fun.(url) do
        {:ok, result} -> {:halt, {:ok, result}}
        {:error, :provider_unavailable} = error -> {:halt, error}
        {:error, _reason} -> {:cont, {:error, :oauth_not_supported}}
      end
    end)
  end

  # Only the status and headers matter, so the body (possibly an endless
  # event stream) is never read.
  defp probe(endpoint) do
    body = %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{
        protocolVersion: @protocol_version,
        capabilities: %{},
        clientInfo: %{name: "Tuist", version: "1.0.0"}
      }
    }

    headers = [{"accept", "application/json, text/event-stream"}, {"mcp-protocol-version", @protocol_version}]

    case send_pinned("POST", URI.to_string(endpoint), [json: body, headers: headers], headers_only: true) do
      {:ok, %{status: status, headers: headers}} -> {:ok, status, headers}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(method, url, options \\ []) do
    with {:ok, uri} <- https_uri(url) do
      case send_pinned(method, URI.to_string(uri), options, max_body_bytes: @max_response_bytes) do
        {:ok, %{status: status, body: body}} when status in 200..299 -> decode(body)
        {:ok, %{status: status}} -> {:error, {:http_status, status}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # One unpooled connection per request through `PinnedHTTP`: these hosts are
  # user-controlled, and Req would start a permanent, atom-named pool for each
  # one. Every response is bounded in size and in total time, and the total
  # stays below the refresh lease.
  defp send_pinned(method, url, options, client_options) do
    {content_type, body} =
      cond do
        json = options[:json] -> {"application/json", JSON.encode!(json)}
        form = options[:form] -> {"application/x-www-form-urlencoded", URI.encode_query(form)}
        true -> {nil, nil}
      end

    headers =
      Keyword.get(options, :headers, [{"accept", "application/json"}]) ++
        if(content_type, do: [{"content-type", content_type}], else: [])

    with {:ok, pinned, host} <- pin(url) do
      case PinnedHTTP.request(
             method,
             pinned,
             [
               headers: headers,
               body: body,
               connect_options: SSRFGuard.connect_options(host) ++ [timeout: 5_000],
               receive_timeout: 10_000,
               total_timeout: @request_deadline_ms
             ] ++ client_options
           ) do
        {:ok, response} -> {:ok, %{response | headers: normalize_headers(response.headers)}}
        {:error, _reason} -> {:error, :provider_unavailable}
      end
    end
  end

  defp normalize_headers(headers) do
    Enum.group_by(headers, fn {name, _value} -> String.downcase(name) end, fn {_name, value} -> value end)
  end

  defp decode(body) do
    case JSON.decode(body) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp pin(url) do
    case SSRFGuard.pin(url) do
      {:ok, pinned, host} -> {:ok, pinned, host}
      # Private and unresolvable hosts fail alike, so errors do not reveal
      # which internal names exist.
      {:error, _reason} -> {:error, :provider_unavailable}
    end
  end

  @doc "Parses an HTTPS URL without credentials or fragments, the only kind Tuist calls."
  def https_uri(url) when is_binary(url) and byte_size(url) <= 2048 do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host, userinfo: nil, fragment: nil} = uri} when is_binary(host) and host != "" ->
        {:ok, uri}

      _ ->
        {:error, :invalid_url}
    end
  end

  def https_uri(_url), do: {:error, :invalid_url}

  defp origin(%URI{scheme: scheme, host: host, port: port}) do
    if port == URI.default_port(scheme), do: "#{scheme}://#{host}", else: "#{scheme}://#{host}:#{port}"
  end

  defp path(%URI{path: path}) when path in [nil, "", "/"], do: ""
  defp path(%URI{path: path}), do: String.trim_trailing(path, "/")

  defp scopes(scopes) when is_list(scopes) do
    case Enum.filter(scopes, &is_binary/1) do
      [] -> nil
      scopes -> Enum.join(scopes, " ")
    end
  end

  defp scopes(_scopes), do: nil

  defp string_or_nil(value) when is_binary(value) and value != "", do: value
  defp string_or_nil(_value), do: nil

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
end
