defmodule Atlas.MCP.OAuth do
  @moduledoc """
  OAuth helpers for upstream MCP servers that require per-user authorization.
  """

  alias Atlas.MCP
  alias Atlas.MCP.Proxy.Server
  alias Atlas.Users.User
  alias AtlasWeb.Endpoint

  @state_salt "mcp-oauth-state"

  def authorization_url(%Server{auth_type: :oauth2} = server, %User{} = user, redirect_uri, return_to) do
    with {:ok, client} <- client_for_authorization(server, redirect_uri) do
      code_verifier = code_verifier()

      state =
        Phoenix.Token.sign(Endpoint, @state_salt, %{
          "server" => server.name,
          "user_id" => user.id,
          "code_verifier" => code_verifier,
          "client_id" => client.client_id,
          "client_secret" => client.client_secret,
          "return_to" => return_to || "/admin/mcps"
        })

      params =
        %{
          "response_type" => "code",
          "client_id" => client.client_id,
          "redirect_uri" => redirect_uri,
          "state" => state,
          "code_challenge" => code_challenge(code_verifier),
          "code_challenge_method" => "S256"
        }
        |> maybe_put_scope(server.scopes)
        |> Map.merge(server.authorization_params)

      {:ok, server.authorization_url <> "?" <> URI.encode_query(params)}
    end
  end

  def authorization_url(%Server{}, _user, _redirect_uri, _return_to), do: {:error, :unsupported_auth_type}

  def handle_callback(%User{} = user, server_name, params, redirect_uri) do
    with {:ok, %Server{} = server} <- MCP.get_server(server_name),
         {:ok, state} <- verify_state(params["state"]),
         :ok <- validate_state(state, user, server),
         code when is_binary(code) <- params["code"],
         client = %{
           client_id: state["client_id"] || server.client_id,
           client_secret: state["client_secret"] || server.client_secret
         },
         {:ok, attrs} <- exchange_code(server, code, state["code_verifier"], redirect_uri, client),
         {:ok, session} <- MCP.upsert_oauth_session(user, server, attrs) do
      {:ok, session, state["return_to"] || "/admin/mcps"}
    else
      nil -> {:error, :missing_code}
      {:error, _reason} = error -> error
      :error -> {:error, :invalid_state}
    end
  end

  def refresh_token(%Server{} = server, refresh_token, client) when is_binary(refresh_token) and refresh_token != "" do
    body =
      %{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_token
      }
      |> maybe_put_client_id(client.client_id)
      |> maybe_put_client_secret(client.client_secret)

    token_request(server, body)
  end

  def refresh_token(_server, _refresh_token, _client), do: {:error, :missing_refresh_token}

  defp client_for_authorization(%Server{client_id: client_id, client_secret: client_secret}, _redirect_uri)
       when is_binary(client_id) and client_id != "" do
    {:ok, %{client_id: client_id, client_secret: client_secret}}
  end

  defp client_for_authorization(%Server{registration_url: registration_url} = server, redirect_uri)
       when is_binary(registration_url) and registration_url != "" do
    register_client(server, redirect_uri)
  end

  defp client_for_authorization(_server, _redirect_uri), do: {:error, :missing_client_registration}

  defp register_client(%Server{} = server, redirect_uri) do
    body = %{
      "client_name" => "Atlas #{server.name}",
      "redirect_uris" => [redirect_uri],
      "grant_types" => ["authorization_code", "refresh_token"],
      "response_types" => ["code"],
      "token_endpoint_auth_method" => "none"
    }

    request =
      Req.new(
        url: server.registration_url,
        headers: [{"accept", "application/json"} | server.token_headers],
        json: body,
        receive_timeout: server.receive_timeout
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: status, body: %{"client_id" => client_id} = body}} when status in 200..299 ->
        {:ok, %{client_id: client_id, client_secret: body["client_secret"]}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:registration_failed, status, body}}

      {:error, reason} ->
        {:error, {:registration_failed, reason}}
    end
  end

  defp exchange_code(%Server{} = server, code, code_verifier, redirect_uri, client) do
    body =
      %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => redirect_uri,
        "code_verifier" => code_verifier
      }
      |> maybe_put_client_id(client.client_id)
      |> maybe_put_client_secret(client.client_secret)

    token_request(server, body)
    |> with_client(client)
  end

  defp token_request(%Server{} = server, body) do
    request =
      Req.new(
        url: server.token_url,
        headers: [{"accept", "application/json"} | server.token_headers],
        form: body,
        receive_timeout: server.receive_timeout
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 and is_map(body) ->
        token_attrs(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp token_attrs(%{"access_token" => access_token} = body) when is_binary(access_token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok,
     %{
       access_token: access_token,
       refresh_token: body["refresh_token"],
       token_type: body["token_type"] || "Bearer",
       scopes: scopes(body["scope"]),
       expires_at: expires_at(body["expires_in"], now),
       last_refreshed_at: now
     }}
  end

  defp token_attrs(_body), do: {:error, :missing_access_token}

  defp with_client({:ok, attrs}, client) do
    {:ok, Map.merge(attrs, %{client_id: client.client_id, client_secret: client.client_secret})}
  end

  defp with_client({:error, _reason} = error, _client), do: error

  defp verify_state(state) when is_binary(state) do
    Phoenix.Token.verify(Endpoint, @state_salt, state, max_age: 600)
  end

  defp verify_state(_state), do: {:error, :missing_state}

  defp validate_state(%{"user_id" => user_id, "server" => server_name}, %User{id: user_id}, %Server{name: server_name}) do
    :ok
  end

  defp validate_state(_state, _user, _server), do: {:error, :invalid_state}

  defp maybe_put_scope(params, scopes) when is_list(scopes) and scopes != [] do
    Map.put(params, "scope", Enum.join(scopes, " "))
  end

  defp maybe_put_scope(params, _scopes), do: params

  defp maybe_put_client_id(params, client_id) when is_binary(client_id) and client_id != "" do
    Map.put(params, "client_id", client_id)
  end

  defp maybe_put_client_id(params, _client_id), do: params

  defp maybe_put_client_secret(params, secret) when is_binary(secret) and secret != "" do
    Map.put(params, "client_secret", secret)
  end

  defp maybe_put_client_secret(params, _secret), do: params

  defp scopes(nil), do: []
  defp scopes(scope) when is_binary(scope), do: String.split(scope, " ", trim: true)
  defp scopes(scopes) when is_list(scopes), do: scopes
  defp scopes(_scope), do: []

  defp expires_at(nil, now), do: DateTime.add(now, 3600, :second)
  defp expires_at(seconds, now) when is_integer(seconds), do: DateTime.add(now, seconds, :second)

  defp expires_at(seconds, now) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {parsed, ""} -> expires_at(parsed, now)
      _ -> expires_at(nil, now)
    end
  end

  defp expires_at(_seconds, now), do: expires_at(nil, now)

  defp code_verifier do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp code_challenge(verifier) do
    :sha256
    |> :crypto.hash(verifier)
    |> Base.url_encode64(padding: false)
  end
end
