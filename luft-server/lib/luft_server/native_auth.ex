defmodule LuftServer.NativeAuth do
  @moduledoc "Boruta's native OAuth boundary, backed by Luft's upstream-credential sessions."
  @behaviour Boruta.Oauth.AuthorizeApplication
  @behaviour Boruta.Oauth.TokenApplication

  import Ecto.Query

  alias Boruta.Ecto.Token
  alias Boruta.Oauth
  alias Boruta.Oauth.Authorization.AccessToken
  alias Boruta.Oauth.AuthorizationCodeRequest
  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.RefreshTokenRequest
  alias Boruta.Oauth.Request
  alias Boruta.Oauth.ResourceOwner
  alias LuftServer.AuthEvents
  alias LuftServer.OAuth.Clients
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Sessions.Session

  defdelegate client_id(), to: Clients

  # Application policy on top of Boruta: only this native client, S256, no
  # downstream scopes, and canonical registered native/loopback redirects.
  def validate_request(params) do
    with false <- request_object?(params),
         %{
           "response_type" => "code",
           "code_challenge_method" => "S256",
           "code_challenge" => challenge,
           "state" => state,
           "redirect_uri" => redirect_uri
         } <- params,
         true <- is_binary(challenge) and Regex.match?(~r/\A[A-Za-z0-9_-]{43}\z/, challenge),
         true <- is_binary(state) and byte_size(state) in 1..2048,
         true <- params["scope"] in [nil, ""],
         true <- valid_redirect?(redirect_uri),
         request =
           Map.take(
             params,
             ~w(client_id response_type code_challenge_method code_challenge state redirect_uri)
           ),
         :ok <-
           Oauth.preauthorize(authorize_conn(request), %ResourceOwner{sub: "pending"}, __MODULE__) do
      {:ok, request}
    else
      _ -> {:error, :invalid_request}
    end
  end

  def valid_redirect?("luft://oauth-callback"), do: true

  def valid_redirect?(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{
        scheme: "http",
        host: "127.0.0.1",
        port: port,
        path: "/callback",
        userinfo: nil,
        query: nil,
        fragment: nil
      } ->
        is_integer(port) and port in 1..65_535 and uri == "http://127.0.0.1:#{port}/callback"

      _ ->
        false
    end
  end

  def valid_redirect?(_uri), do: false

  def complete(signin, request) do
    Repo.transaction(fn ->
      with {:ok, _token, session} <- Sessions.create(signin),
           {:ok, url} <-
             Oauth.authorize(authorize_conn(request), %ResourceOwner{sub: session.id}, __MODULE__) do
        {url, session}
      else
        _ -> Repo.rollback(:invalid_request)
      end
    end)
    |> case do
      {:ok, {url, session}} -> {:ok, url, session}
      error -> error
    end
  end

  def callback_url(request, query) do
    request["redirect_uri"] <>
      "?" <> URI.encode_query(Map.put(Map.new(query), :state, request["state"]))
  end

  def exchange(%Plug.Conn{} = conn) do
    # Boruta resolves unsigned request objects (including HTTP fetches) before
    # client authentication. Luft supports neither JAR nor PAR on any flow.
    with false <- request_object?(conn.query_params),
         false <- request_object?(conn.body_params),
         {:ok, request} <- Request.token_request(conn),
         true <- Map.get(request, :client_id) == client_id(),
         {:ok, query} <- grant_query(request),
         true <- valid_credential?(query[:value] || query[:refresh_token]) do
      event = if match?(%RefreshTokenRequest{}, request), do: :refresh, else: :code_exchange

      # Upstream adapters remain unmodified. Lock the owning session before
      # Boruta rereads and spends the code/refresh token, and commit its writes
      # together with the retry response. All replicas use this same DB lock.
      # Failures roll back with their outcome and the session, if known, for
      # the authentication event.
      Repo.transaction(fn ->
        token = Repo.get_by(Token, query) || Repo.rollback({:invalid_grant, nil})

        # A revoked grant presented again is a replayed code or refresh token.
        if token.revoked_at,
          do: Repo.rollback({:reused, Sessions.get_by_id(token.sub) || token.sub})

        session =
          Repo.one(
            from s in Session,
              where: s.id == ^token.sub and s.expires_at > ^DateTime.utc_now(),
              lock: "FOR UPDATE"
          ) ||
            Repo.rollback({:session_expired, token.sub})

        exchange_locked(conn, request, token, session)
      end)
      |> case do
        {:ok, {response, outcome, session}} ->
          AuthEvents.log(event, outcome, client: client_id(), session: session)
          {:ok, response}

        {:error, {outcome, session}} ->
          AuthEvents.log(event, outcome, client: client_id(), session: session)
          {:error, :invalid_grant}
      end
    else
      true ->
        AuthEvents.log(:token, :invalid_request)
        {:error, :invalid_request}

      _ ->
        AuthEvents.log(:token, :invalid_grant)
        {:error, :invalid_grant}
    end
  end

  def exchange(params) when is_map(params), do: exchange(%Plug.Conn{body_params: params})

  defp request_object?(params), do: Enum.any?(~w(request request_uri), &Map.has_key?(params, &1))

  defp grant_query(%AuthorizationCodeRequest{code: code}), do: {:ok, [type: "code", value: code]}

  defp grant_query(%RefreshTokenRequest{refresh_token: token, scope: scope})
       when scope in [nil, ""],
       do: {:ok, [type: "access_token", refresh_token: token]}

  defp grant_query(_request), do: {:error, :invalid_grant}

  defp exchange_locked(conn, %RefreshTokenRequest{refresh_token: value}, token, session) do
    case Sessions.refresh_replay(session, value) do
      {:ok, response} ->
        {response, :retried, session}

      :error ->
        response = issue(conn, token, session)
        Sessions.remember_refresh(session, value, response)
        {response, :success, session}
    end
  end

  defp exchange_locked(conn, %AuthorizationCodeRequest{}, token, session),
    do: {issue(conn, token, session), :success, session}

  defp issue(conn, token, session) do
    case Oauth.token(conn, __MODULE__) do
      {:ok, response} ->
        response

      # A rotated refresh token presented after its retry window.
      {:error, _error} when not is_nil(token.refresh_token_revoked_at) ->
        Repo.rollback({:reused, session})

      {:error, _error} ->
        Repo.rollback({:invalid_grant, session})
    end
  end

  @doc "Boruta validates the stored access grant; a live Luft session is required too."
  def resolve_bearer(token) do
    with true <- valid_credential?(token),
         {:ok, %{sub: id}} <- AccessToken.authorize(value: token) do
      Sessions.get_by_id(id)
    else
      _ -> nil
    end
  end

  defp valid_credential?(token) when is_binary(token) and byte_size(token) in 1..8192,
    do: String.valid?(token) and not String.contains?(token, <<0>>)

  defp valid_credential?(_token), do: false

  defp authorize_conn(params), do: %Plug.Conn{query_params: params}

  @impl true
  def preauthorize_success(_conn, _authorization), do: :ok

  @impl true
  def preauthorize_error(_conn, error), do: {:error, error}

  @impl true
  def authorize_success(_conn, %AuthorizeResponse{} = response),
    do: {:ok, AuthorizeResponse.redirect_to_url(response)}

  @impl true
  def authorize_error(_conn, error), do: {:error, error}

  @impl true
  def token_success(_conn, response) do
    session = Sessions.get_by_id(response.token.sub)
    remaining = DateTime.to_unix(session.expires_at) - System.system_time(:second)

    {:ok,
     response
     |> Map.from_struct()
     |> Map.take([:access_token, :refresh_token, :token_type, :expires_in])
     |> Map.update!(:expires_in, &min(&1, remaining))}
  end

  @impl true
  def token_error(_conn, error), do: {:error, error}
end
