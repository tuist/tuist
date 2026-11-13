defmodule Tuist.Accounts.MCPServers do
  @moduledoc """
  Remote MCP servers a user adds for AI features (gated by
  `Tuist.FeatureFlags.ai_enabled?/1`), and the OAuth sessions Tuist holds for
  them so internal agentic features can call their tools on the user's
  behalf. Authorization follows the MCP specification through
  `Tuist.Accounts.MCPServers.OAuth`.

  Public callers get metadata from `list/1`; only server-side code may call
  `credentials/2`, and its result must never be rendered or serialized.

  State changes serialize on the server's row, but no lock or transaction is
  held while a third party is called. Completing a sign-in consumes its
  single-use state in a short locked step, exchanges the code unlocked, and
  saves the tokens in a second locked step only if the row still exists.
  A refresh claims a lease (`refreshing_until`) the same way, so concurrent
  readers share one refresh and a rotating refresh token is never spent
  twice, and saves its result only if the row still holds the refresh token
  it started from. A removal or reconnect in between therefore wins.
  """

  import Ecto.Query

  alias Tuist.Accounts.MCPServers.OAuth
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserMCPServer
  alias Tuist.RateLimit
  alias Tuist.Repo

  @max_servers 25
  @authorization_lifetime 600
  @refresh_margin 60
  # Longer than a token exchange can take (5s to connect, 10s to receive).
  @refresh_lease 30
  @refresh_wait_ms 25_000
  @refresh_wait_step_ms 200

  @doc "The user's MCP servers, oldest first. Never includes credentials."
  def list(%User{id: user_id}) do
    Repo.all(
      from s in UserMCPServer,
        where: s.user_id == ^user_id,
        order_by: [asc: s.inserted_at, asc: s.id],
        select: %{
          id: s.id,
          name: s.name,
          url: s.url,
          connected: not is_nil(s.access_token),
          updated_at: s.updated_at
        }
    )
  end

  @doc """
  Adds an MCP server by its HTTPS endpoint, without authorizing it yet. Adding
  a URL the user already added returns the existing server.
  """
  def add(%User{} = user, attrs) do
    url = string_attr(attrs, "url")
    name = string_attr(attrs, "name")

    with {:ok, uri} <- OAuth.https_uri(url) do
      url = URI.to_string(uri)
      name = if name == "", do: uri.host, else: name

      case Repo.get_by(UserMCPServer, user_id: user.id, url: url) do
        %UserMCPServer{} = server -> {:ok, server}
        nil -> insert(user, name, url)
      end
    end
  end

  defp string_attr(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) -> String.trim(value)
      _ -> ""
    end
  end

  # Adds for one user serialize on their row, so concurrent adds can neither
  # exceed the limit nor insert the same URL twice.
  defp insert(user, name, url) do
    locked(fn ->
      Repo.one!(from u in User, where: u.id == ^user.id, select: u.id, lock: "FOR NO KEY UPDATE")

      cond do
        server = Repo.get_by(UserMCPServer, user_id: user.id, url: url) ->
          {:ok, server}

        Repo.aggregate(from(s in UserMCPServer, where: s.user_id == ^user.id), :count) >= @max_servers ->
          {:error, :too_many_servers}

        true ->
          case %UserMCPServer{user_id: user.id} |> UserMCPServer.changeset(%{name: name, url: url}) |> Repo.insert() do
            {:ok, server} -> {:ok, server}
            {:error, _changeset} -> {:error, :invalid_name}
          end
      end
    end)
  end

  @doc """
  Discovers the server's authorization server, registers Tuist as a client
  when it has not yet, and returns the URL to send the user's browser to.
  `redirect_uri` is where the authorization server sends the user back;
  `complete_authorization/2` finishes the sign-in there.
  """
  def start_authorization(%User{} = user, server_id, redirect_uri) do
    with %UserMCPServer{} = server <- get(user, server_id),
         {:allow, _count} <- RateLimit.hit("mcp-servers:authorize:#{user.id}", limit: 10, window: to_timeout(minute: 5)),
         {:ok, discovery} <- OAuth.discover(server.url),
         {:ok, client} <- client(server, discovery, redirect_uri) do
      state = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
      code_verifier = OAuth.code_verifier()

      config = %{
        resource: discovery.resource,
        issuer: discovery.issuer,
        authorization_endpoint: discovery.authorization_endpoint,
        token_endpoint: discovery.token_endpoint,
        scope: discovery.scope,
        client_id: client.client_id,
        client_secret: client.client_secret
      }

      pending = %{code_verifier: code_verifier, redirect_uri: redirect_uri, state: state}
      locked(fn -> save_authorization(user, server_id, config, pending) end)
    else
      nil -> {:error, :not_found}
      {:deny, _retry_after} -> {:error, :rate_limited}
      {:error, reason} -> {:error, reason}
    end
  end

  defp save_authorization(user, server_id, config, pending) do
    case get_locked(user, server_id) do
      %UserMCPServer{} = server ->
        attrs =
          config
          # Tokens never follow the row to another authorization server,
          # even one that hands out the same client ID.
          |> Map.merge(if(same_session?(server, config), do: %{}, else: cleared_tokens()))
          |> Map.merge(%{
            pending_authorization: JSON.encode!(Map.take(pending, [:code_verifier, :redirect_uri])),
            pending_state_hash: hash(pending.state),
            pending_expires_at: DateTime.add(now(), @authorization_lifetime, :second)
          })

        with {:ok, saved} <- save(server, attrs) do
          {:ok, OAuth.authorization_url(saved, pending.state, pending.code_verifier, pending.redirect_uri)}
        end

      nil ->
        {:error, :not_found}
    end
  end

  # Reuse the registration while the server keeps its authorization server.
  defp client(%UserMCPServer{client_id: client_id, issuer: issuer} = server, %{issuer: issuer}, _redirect_uri)
       when is_binary(client_id) do
    {:ok, %{client_id: client_id, client_secret: server.client_secret}}
  end

  defp client(_server, discovery, redirect_uri), do: OAuth.register(discovery, redirect_uri)

  @doc """
  Completes the sign-in the authorization server redirected back with. The
  state is single use and bound to the signed-in user: another user's state,
  an expired one, or one already used returns `{:error, :not_found}`.
  """
  def complete_authorization(%User{} = user, %{"state" => state} = params) when is_binary(state) do
    with {:ok, server, pending} <- claim_authorization(user, state) do
      case params do
        # RFC 9207: an authorization server that identifies itself must be the
        # one this sign-in started with.
        %{"iss" => iss} when iss != server.issuer ->
          {:error, :issuer_mismatch}

        %{"code" => code} when is_binary(code) and code != "" ->
          result = OAuth.exchange_code(server, code, pending["code_verifier"], pending["redirect_uri"])
          locked(fn -> finish_authorization(user, server, result) end)

        _denied ->
          {:error, :access_denied}
      end
    end
  end

  def complete_authorization(_user, _params), do: {:error, :not_found}

  defp claim_authorization(user, state) do
    locked(fn ->
      query =
        from s in UserMCPServer,
          where: s.user_id == ^user.id and s.pending_state_hash == ^hash(state),
          lock: "FOR UPDATE"

      with %UserMCPServer{} = server <- Repo.one(query),
           pending = JSON.decode!(server.pending_authorization),
           {:ok, saved} <- save(server, cleared_authorization()) do
        if DateTime.after?(server.pending_expires_at, now()),
          do: {:ok, saved, pending},
          else: {:error, :authorization_expired}
      else
        nil -> {:error, :not_found}
        error -> error
      end
    end)
  end

  defp finish_authorization(user, %UserMCPServer{id: id} = started, result) do
    case get_locked(user, id) do
      # Removed, or re-registered with another authorization server, meanwhile.
      %UserMCPServer{} = server when server.client_id == started.client_id and server.issuer == started.issuer ->
        case result do
          {:ok, tokens} -> save(server, Map.put(tokens, :refreshing_until, nil))
          {:error, _reason} -> {:error, :authorization_failed}
        end

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Deletes the server and the session Tuist stored for it. Upstream
  authorization is not revoked; users revoke it at the provider.
  """
  def remove(%User{} = user, server_id) do
    case Ecto.UUID.cast(server_id) do
      {:ok, id} ->
        Repo.delete_all(from s in UserMCPServer, where: s.user_id == ^user.id and s.id == ^id)
        :ok

      :error ->
        :ok
    end
  end

  @doc """
  Server-side use only: returns the server's endpoint and a usable access
  token, refreshing an expiring one first. Concurrent callers share one
  refresh. Never render or serialize the result.
  """
  def credentials(%User{} = user, server_id) do
    credentials(user, server_id, System.monotonic_time(:millisecond) + @refresh_wait_ms)
  end

  defp credentials(user, server_id, deadline) do
    case claim_credentials(user, server_id) do
      {:refresh, server} ->
        result = OAuth.refresh(server)
        locked(fn -> finish_refresh(user, server, result) end)

      :wait ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(@refresh_wait_step_ms)
          credentials(user, server_id, deadline)
        else
          {:error, :refresh_failed}
        end

      result ->
        result
    end
  end

  defp claim_credentials(user, server_id) do
    locked(fn ->
      case get_locked(user, server_id) do
        %UserMCPServer{access_token: token} = server when is_binary(token) -> claim_refresh(server)
        %UserMCPServer{} -> {:error, :not_connected}
        nil -> {:error, :not_found}
      end
    end)
  end

  defp claim_refresh(server) do
    cond do
      fresh?(server) ->
        {:ok, credentials_for(server)}

      is_nil(server.refresh_token) ->
        with {:ok, _} <- save(server, cleared_tokens()), do: {:error, :reauthorization_required}

      server.refreshing_until && DateTime.after?(server.refreshing_until, now()) ->
        :wait

      true ->
        with {:ok, saved} <- save(server, %{refreshing_until: DateTime.add(now(), @refresh_lease, :second)}) do
          {:refresh, saved}
        end
    end
  end

  defp finish_refresh(user, %UserMCPServer{id: id} = started, result) do
    case get_locked(user, id) do
      # Still the session this refresh started from, with the same authorization server.
      %UserMCPServer{} = server
      when server.refresh_token == started.refresh_token and server.client_id == started.client_id and
             server.issuer == started.issuer and server.token_endpoint == started.token_endpoint ->
        save_refresh(server, result)

      # Reconnected with a new session while the authorization server answered.
      %UserMCPServer{access_token: token} = server when is_binary(token) ->
        if fresh?(server), do: {:ok, credentials_for(server)}, else: {:error, :refresh_failed}

      %UserMCPServer{} ->
        {:error, :not_connected}

      nil ->
        {:error, :not_found}
    end
  end

  defp save_refresh(server, {:ok, tokens}) do
    with {:ok, saved} <- save(server, Map.put(tokens, :refreshing_until, nil)) do
      {:ok, credentials_for(saved)}
    end
  end

  # The authorization server rejected the refresh token; the user has to sign in again.
  defp save_refresh(server, {:error, {:http_status, status}}) when status in [400, 401, 403] do
    with {:ok, _} <- save(server, cleared_tokens()), do: {:error, :reauthorization_required}
  end

  defp save_refresh(server, {:error, _reason}) do
    with {:ok, _} <- save(server, %{refreshing_until: nil}), do: {:error, :refresh_failed}
  end

  defp same_session?(server, other) do
    server.client_id == other.client_id and server.issuer == other.issuer and
      server.token_endpoint == other.token_endpoint
  end

  defp credentials_for(server), do: %{id: server.id, url: server.url, access_token: server.access_token}

  defp fresh?(%UserMCPServer{expires_at: nil}), do: true

  defp fresh?(%UserMCPServer{expires_at: expires_at}),
    do: DateTime.after?(expires_at, DateTime.add(now(), @refresh_margin, :second))

  defp cleared_tokens, do: %{access_token: nil, refresh_token: nil, expires_at: nil, refreshing_until: nil}

  defp cleared_authorization, do: %{pending_authorization: nil, pending_state_hash: nil, pending_expires_at: nil}

  defp hash(state), do: :crypto.hash(:sha256, state)

  defp now, do: DateTime.utc_now(:second)

  defp get(user, server_id) do
    case Ecto.UUID.cast(server_id) do
      {:ok, id} -> Repo.get_by(UserMCPServer, user_id: user.id, id: id)
      :error -> nil
    end
  end

  defp get_locked(user, server_id) do
    case Ecto.UUID.cast(server_id) do
      {:ok, id} -> Repo.one(from s in UserMCPServer, where: s.user_id == ^user.id and s.id == ^id, lock: "FOR UPDATE")
      :error -> nil
    end
  end

  defp save(server, attrs) do
    case server |> UserMCPServer.changeset(attrs) |> Repo.update() do
      {:ok, saved} -> {:ok, saved}
      {:error, _changeset} -> {:error, :storage_unavailable}
    end
  end

  # Short transactions only: none of them calls a third party. The lock
  # timeout bounds the wait behind another caller holding the same row.
  defp locked(fun) do
    fn ->
      Repo.query!("SET LOCAL lock_timeout = '5s'")
      fun.()
    end
    |> Repo.transaction(timeout: 15_000)
    |> case do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :storage_unavailable}
  end
end
