defmodule Atlas.LLMs.Connections do
  @moduledoc """
  Personal provider credentials, separate from Atlas's application-wide LLM.
  Public surfaces use `list/1`, never credential-bearing schemas. All mutations
  serialize on the owner row, including remote exchanges, so disconnecting cannot
  be undone by an in-flight login or refresh on another replica.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.LLMs.ChatGPT
  alias Atlas.LLMs.Connection
  alias Atlas.RateLimit
  alias Atlas.Repo
  alias Atlas.Users.User
  alias Atlas.UUIDv7

  @providers ["claude", "chatgpt"]
  @login_lifetime 900

  def list(%User{id: user_id}) do
    connections =
      Repo.all(
        from c in Connection,
          where: c.user_id == ^user_id,
          select: %{
            provider: c.provider,
            credential_configured: not is_nil(c.access_token),
            expires_at: c.expires_at,
            updated_at: c.updated_at
          }
      )

    Enum.map(@providers, fn provider ->
      connection = Enum.find(connections, &(&1.provider == provider))
      metadata(provider, connection)
    end)
  end

  def connect_claude(%User{} = user, token) do
    if valid_claude_token?(token) do
      locked(user, fn ->
        connection = get(user, "claude") || %Connection{user_id: user.id, provider: "claude"}

        with {:ok, saved} <- save(connection, %{access_token: String.trim(token)}) do
          audit(user, "connected", "claude")
          {:ok, metadata("claude", saved)}
        end
      end)
    else
      {:error, :invalid_claude_token}
    end
  end

  def start_chatgpt(%User{} = user) do
    case RateLimit.hit("chatgpt-login:#{user.id}", 300_000, 5) do
      {:allow, _count} -> start_chatgpt_login(user)
      {:deny, _remaining} -> {:error, :rate_limited}
    end
  end

  defp start_chatgpt_login(user) do
    locked(user, fn ->
      connection = get(user, "chatgpt") || %Connection{user_id: user.id, provider: "chatgpt"}

      if connection.pending_expires_at && DateTime.after?(connection.pending_expires_at, now()) do
        {:error, :login_in_progress}
      else
        with {:ok, login} <- ChatGPT.start(),
             login = Map.put(login, "id", UUIDv7.generate()),
             {:ok, saved} <-
               save(connection, %{
                 pending_login: JSON.encode!(login),
                 pending_expires_at: DateTime.add(now(), @login_lifetime, :second),
                 next_poll_at: DateTime.add(now(), login["interval"], :second)
               }) do
          audit(user, "login_started", "chatgpt")

          {:ok,
           %{
             login_id: login["id"],
             user_code: login["user_code"],
             verification_url: login["verification_url"],
             interval: login["interval"],
             expires_at: saved.pending_expires_at
           }}
        end
      end
    end)
  end

  def poll_chatgpt(%User{} = user, login_id) when is_binary(login_id) do
    locked(user, fn ->
      case get(user, "chatgpt") do
        %Connection{pending_login: pending} = connection when is_binary(pending) ->
          login = JSON.decode!(pending)

          cond do
            login["id"] != login_id -> {:error, :not_found}
            !DateTime.after?(connection.pending_expires_at, now()) -> expire_login(user, connection)
            DateTime.after?(connection.next_poll_at, now()) -> {:ok, %{status: "pending"}}
            true -> poll_login(user, connection, login)
          end

        _ ->
          {:error, :not_found}
      end
    end)
  end

  def poll_chatgpt(_user, _login_id), do: {:error, :not_found}

  def cancel_chatgpt(%User{} = user, login_id) do
    locked(user, fn ->
      with %Connection{pending_login: pending} = connection when is_binary(pending) <- get(user, "chatgpt"),
           true <- JSON.decode!(pending)["id"] == login_id,
           {:ok, _saved} <- save(connection, cleared_login()) do
        audit(user, "login_cancelled", "chatgpt")
        {:ok, %{status: "cancelled"}}
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :not_found}
      end
    end)
  end

  def disconnect(%User{} = user, provider) when provider in @providers do
    locked(user, fn ->
      from(c in Connection, where: c.user_id == ^user.id and c.provider == ^provider) |> Repo.delete_all()
      audit(user, "disconnected", provider)
      {:ok, metadata(provider, nil)}
    end)
  end

  def disconnect(_user, _provider), do: {:error, :unsupported_provider}

  @doc "Server-side use only. Never serialize this result to an API, MCP tool, or LiveView."
  def credentials(%User{} = user, provider) when provider in @providers do
    locked(user, fn ->
      case get(user, provider) do
        %Connection{access_token: token} = connection when is_binary(token) ->
          if provider == "chatgpt" and !DateTime.after?(connection.expires_at, DateTime.add(now(), 60, :second)) do
            refresh(user, connection)
          else
            {:ok, %{provider: provider, access_token: token}}
          end

        _ ->
          {:error, :not_connected}
      end
    end)
  end

  def credentials(_user, _provider), do: {:error, :unsupported_provider}

  defp poll_login(user, connection, login) do
    case ChatGPT.poll(login) do
      {:ok, tokens} ->
        with {:ok, _saved} <- save(connection, Map.merge(tokens, cleared_login())) do
          audit(user, "connected", "chatgpt")
          {:ok, %{status: "connected"}}
        end

      {:error, :authorization_pending} ->
        with {:ok, _saved} <- save(connection, %{next_poll_at: DateTime.add(now(), login["interval"], :second)}) do
          {:ok, %{status: "pending"}}
        end

      {:error, reason} ->
        if transient?(reason) do
          with {:ok, _saved} <- save(connection, %{next_poll_at: DateTime.add(now(), login["interval"], :second)}) do
            {:error, :provider_unavailable}
          end
        else
          save(connection, cleared_login())
          audit(user, "login_failed", "chatgpt")
          {:error, :chatgpt_login_failed}
        end
    end
  end

  defp refresh(user, connection) do
    case ChatGPT.refresh(connection.refresh_token) do
      {:ok, tokens} ->
        with {:ok, saved} <- save(connection, tokens) do
          audit(user, "refreshed", "chatgpt")
          {:ok, %{provider: "chatgpt", access_token: saved.access_token}}
        end

      {:error, reason} ->
        if match?({:http_status, status} when status in [400, 401, 403], reason) do
          save(connection, %{access_token: nil, refresh_token: nil, expires_at: nil})
          audit(user, "reauthorization_required", "chatgpt")
        end

        {:error, :chatgpt_refresh_failed}
    end
  end

  defp expire_login(user, connection) do
    save(connection, cleared_login())
    audit(user, "login_expired", "chatgpt")
    {:error, :login_expired}
  end

  defp cleared_login, do: %{pending_login: nil, pending_expires_at: nil, next_poll_at: nil}
  defp transient?(:provider_unavailable), do: true
  defp transient?({:http_status, status}), do: status == 429 or status >= 500
  defp transient?(_reason), do: false

  defp valid_claude_token?(token) when is_binary(token) do
    token = String.trim(token)
    byte_size(token) in 32..4096 and Regex.match?(~r/\Ask-ant-oat01-[A-Za-z0-9_-]+\z/, token)
  end

  defp valid_claude_token?(_token), do: false
  defp now, do: DateTime.utc_now(:second)

  defp get(user, provider), do: Repo.get_by(Connection, user_id: user.id, provider: provider)
  defp save(connection, attrs), do: connection |> Connection.changeset(attrs) |> Repo.insert_or_update()

  defp locked(user, fun) do
    result =
      Repo.transaction(
        fn ->
          case Repo.one(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE") do
            nil -> {:error, :not_found}
            _user -> fun.()
          end
        end,
        timeout: 60_000
      )

    case result do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp metadata(provider, connection) do
    %{
      provider: provider,
      credential_configured: configured?(connection),
      expires_at: connection && connection.expires_at,
      updated_at: connection && connection.updated_at,
      login_available: provider == "claude" or match?({:ok, _}, ChatGPT.client_id())
    }
  end

  defp configured?(nil), do: false
  defp configured?(%{credential_configured: configured}), do: configured
  defp configured?(%Connection{access_token: token}), do: is_binary(token)

  defp audit(user, action, provider) do
    Audit.record(
      "llm_provider.#{action}",
      %{
        target_type: "user_llm_connection",
        target_id: user.id,
        target_label: provider,
        metadata: %{provider: provider, path: "/settings/llm-providers"}
      },
      actor: user
    )
  end
end
