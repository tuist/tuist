defmodule Tuist.Accounts.AISubscriptions do
  @moduledoc """
  Personal Claude and ChatGPT subscriptions a user connects for AI features
  (gated by `Tuist.FeatureFlags.ai_enabled?/1`).

  Claude connects with the subscription token `claude setup-token` prints.
  ChatGPT connects through OpenAI's device authorization
  (`Tuist.Accounts.AISubscriptions.ChatGPT`). Public callers get metadata from
  `list/1`; only server-side inference code may call `credentials/2`, and its
  result must never be rendered or serialized.

  State changes serialize on the owning user row, but no lock or transaction
  is held while OpenAI is called. A poll or refresh claims its slot in a short
  locked step (`next_poll_at`, `refreshing_until`), calls OpenAI unlocked, and
  saves its result in a second locked step only if the row still holds the
  same sign-in or refresh token. A disconnect or cancel in between therefore
  wins, and concurrent callers never stack up on database connections.
  """

  import Ecto.Query

  alias Tuist.Accounts.AISubscriptions.ChatGPT
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserAISubscription
  alias Tuist.RateLimit
  alias Tuist.Repo

  @providers [:claude, :chatgpt]
  @login_lifetime 900
  @refresh_margin 60
  # Longer than an OpenAI exchange can take (5s to connect, 15s to receive).
  @refresh_lease 30
  @refresh_wait_ms 25_000
  @refresh_wait_step_ms 200

  def providers, do: @providers

  @doc "Connection metadata for every provider, in display order. Never includes credentials."
  def list(%User{id: user_id}) do
    connected =
      Repo.all(
        from s in UserAISubscription,
          where: s.user_id == ^user_id and not is_nil(s.access_token),
          select: {s.provider, s.updated_at}
      )

    Enum.map(@providers, fn provider ->
      updated_at = connected |> List.keyfind(provider, 0, {provider, nil}) |> elem(1)

      %{
        provider: provider,
        connected: not is_nil(updated_at),
        updated_at: updated_at,
        login_available: provider == :claude or match?({:ok, _}, ChatGPT.client_id())
      }
    end)
  end

  @doc """
  Saves a Claude subscription token from `claude setup-token`. This validates
  the token's format only; it does not prove the subscription can serve
  inference.
  """
  def connect_claude(%User{} = user, token) do
    if valid_claude_token?(token) do
      locked(user, fn ->
        with {:ok, _subscription} <- user |> get_or_build(:claude) |> save(%{access_token: String.trim(token)}) do
          :ok
        end
      end)
    else
      {:error, :invalid_claude_token}
    end
  end

  @doc """
  Starts a ChatGPT device sign-in, replacing any sign-in still pending (for
  example one whose login ID a closed page lost). Returns the opaque login ID
  to poll with and the code the user enters on OpenAI's verification page.
  """
  def start_chatgpt(%User{} = user) do
    case RateLimit.hit("ai-subscriptions:chatgpt-login:#{user.id}", limit: 5, window: to_timeout(minute: 5)) do
      {:allow, _count} -> do_start_chatgpt(user)
      {:deny, _retry_after} -> {:error, :rate_limited}
    end
  end

  defp do_start_chatgpt(user) do
    with {:ok, login} <- ChatGPT.start() do
      login = Map.put(login, "id", Ecto.UUID.generate())

      locked(user, fn ->
        with {:ok, saved} <-
               user
               |> get_or_build(:chatgpt)
               |> save(%{
                 pending_login: JSON.encode!(login),
                 pending_expires_at: DateTime.add(now(), @login_lifetime, :second),
                 next_poll_at: DateTime.add(now(), login["interval"], :second)
               }) do
          {:ok,
           %{
             login_id: login["id"],
             user_code: login["user_code"],
             verification_url: login["verification_url"],
             interval: login["interval"],
             expires_at: saved.pending_expires_at
           }}
        end
      end)
    end
  end

  @doc """
  Polls a ChatGPT sign-in. Returns `{:ok, :pending}` until the user approves
  the code (or until the upstream polling interval allows another request),
  then `{:ok, :connected}`. A sign-in cancelled, replaced or disconnected
  while OpenAI answered returns `{:error, :not_found}` and saves nothing.
  """
  def poll_chatgpt(%User{} = user, login_id) when is_binary(login_id) do
    with {:poll, login} <- claim_poll(user, login_id) do
      result = ChatGPT.poll(login)
      locked(user, fn -> finish_poll(user, login, result) end)
    end
  end

  def poll_chatgpt(_user, _login_id), do: {:error, :not_found}

  defp claim_poll(user, login_id) do
    locked(user, fn ->
      with %UserAISubscription{} = subscription <- get(user, :chatgpt),
           {:ok, login} <- pending_login(subscription, login_id) do
        claim_poll_slot(subscription, login)
      else
        _ -> {:error, :not_found}
      end
    end)
  end

  defp claim_poll_slot(subscription, login) do
    cond do
      not DateTime.after?(subscription.pending_expires_at, now()) ->
        with {:ok, _} <- save(subscription, cleared_login()), do: {:error, :login_expired}

      DateTime.after?(subscription.next_poll_at, now()) ->
        {:ok, :pending}

      true ->
        # Claiming the slot first makes concurrent polls answer pending
        # instead of each calling OpenAI.
        with {:ok, _} <- save(subscription, %{next_poll_at: DateTime.add(now(), login["interval"], :second)}) do
          {:poll, login}
        end
    end
  end

  defp finish_poll(user, login, result) do
    with %UserAISubscription{} = subscription <- get(user, :chatgpt),
         {:ok, _login} <- pending_login(subscription, login["id"]) do
      save_poll_result(subscription, login, result)
    else
      _ -> {:error, :not_found}
    end
  end

  defp save_poll_result(subscription, login, {:ok, tokens}) do
    attrs = tokens |> Map.merge(cleared_login()) |> Map.merge(%{client_id: login["client_id"], refreshing_until: nil})
    with {:ok, _} <- save(subscription, attrs), do: {:ok, :connected}
  end

  defp save_poll_result(subscription, _login, {:error, reason}) do
    if reason == :authorization_pending or transient?(reason) do
      {:ok, :pending}
    else
      with {:ok, _} <- save(subscription, cleared_login()), do: {:error, :chatgpt_login_failed}
    end
  end

  @doc "Cancels a pending ChatGPT sign-in, keeping any saved credentials."
  def cancel_chatgpt(%User{} = user, login_id) do
    locked(user, fn ->
      with %UserAISubscription{} = subscription <- get(user, :chatgpt),
           {:ok, _login} <- pending_login(subscription, login_id),
           {:ok, _} <- save(subscription, cleared_login()) do
        :ok
      else
        _ -> {:error, :not_found}
      end
    end)
  end

  @doc """
  Deletes the provider's saved credentials and any pending sign-in. Upstream
  authorization is not revoked; users revoke it at the provider.
  """
  def disconnect(%User{} = user, provider) when provider in @providers do
    locked(user, fn ->
      Repo.delete_all(from s in UserAISubscription, where: s.user_id == ^user.id and s.provider == ^provider)
      :ok
    end)
  end

  @doc """
  Server-side use only: returns a usable access token for the provider,
  refreshing an expiring ChatGPT token first. Concurrent callers share one
  refresh. Never render or serialize the result.
  """
  def credentials(%User{} = user, provider) when provider in @providers do
    credentials(user, provider, System.monotonic_time(:millisecond) + @refresh_wait_ms)
  end

  defp credentials(user, provider, deadline) do
    case claim_credentials(user, provider) do
      {:refresh, refresh_token, client_id} ->
        result = ChatGPT.refresh(refresh_token, client_id)
        locked(user, fn -> finish_refresh(user, refresh_token, result) end)

      :wait ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(@refresh_wait_step_ms)
          credentials(user, provider, deadline)
        else
          {:error, :chatgpt_refresh_failed}
        end

      result ->
        result
    end
  end

  defp claim_credentials(user, provider) do
    locked(user, fn ->
      case get(user, provider) do
        %UserAISubscription{provider: :chatgpt, access_token: token} = subscription when is_binary(token) ->
          claim_chatgpt_refresh(subscription)

        %UserAISubscription{access_token: token} when is_binary(token) ->
          {:ok, %{provider: provider, access_token: token}}

        _ ->
          {:error, :not_connected}
      end
    end)
  end

  defp claim_chatgpt_refresh(subscription) do
    cond do
      fresh?(subscription) ->
        {:ok, %{provider: :chatgpt, access_token: subscription.access_token}}

      subscription.refreshing_until && DateTime.after?(subscription.refreshing_until, now()) ->
        :wait

      true ->
        with {:ok, _} <- save(subscription, %{refreshing_until: DateTime.add(now(), @refresh_lease, :second)}) do
          {:refresh, subscription.refresh_token, subscription.client_id}
        end
    end
  end

  defp finish_refresh(user, refresh_token, result) do
    case get(user, :chatgpt) do
      # Still the credentials this refresh started from.
      %UserAISubscription{refresh_token: ^refresh_token} = subscription ->
        case result do
          {:ok, tokens} ->
            with {:ok, saved} <- save(subscription, Map.put(tokens, :refreshing_until, nil)) do
              {:ok, %{provider: :chatgpt, access_token: saved.access_token}}
            end

          {:error, {:http_status, status}} when status in [400, 401, 403] ->
            # The provider rejected the refresh token; the user has to sign in again.
            attrs = %{access_token: nil, refresh_token: nil, expires_at: nil, refreshing_until: nil}
            with {:ok, _} <- save(subscription, attrs), do: {:error, :reauthorization_required}

          {:error, _reason} ->
            with {:ok, _} <- save(subscription, %{refreshing_until: nil}), do: {:error, :chatgpt_refresh_failed}
        end

      # Disconnected, or reconnected with new credentials, while OpenAI answered.
      %UserAISubscription{access_token: token} = subscription when is_binary(token) ->
        if fresh?(subscription),
          do: {:ok, %{provider: :chatgpt, access_token: token}},
          else: {:error, :chatgpt_refresh_failed}

      _ ->
        {:error, :not_connected}
    end
  end

  defp fresh?(%UserAISubscription{expires_at: %DateTime{} = expires_at}),
    do: DateTime.after?(expires_at, DateTime.add(now(), @refresh_margin, :second))

  defp fresh?(_subscription), do: false

  defp pending_login(%UserAISubscription{pending_login: pending}, login_id) when is_binary(pending) do
    case JSON.decode!(pending) do
      %{"id" => ^login_id} = login -> {:ok, login}
      _ -> :error
    end
  end

  defp pending_login(_subscription, _login_id), do: :error

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

  defp get(user, provider), do: Repo.get_by(UserAISubscription, user_id: user.id, provider: provider)

  defp get_or_build(user, provider), do: get(user, provider) || %UserAISubscription{user_id: user.id, provider: provider}

  defp save(subscription, attrs) do
    case subscription |> UserAISubscription.changeset(attrs) |> Repo.insert_or_update() do
      {:ok, saved} -> {:ok, saved}
      {:error, _changeset} -> {:error, :storage_unavailable}
    end
  end

  # Short transactions only: none of them calls OpenAI. `FOR NO KEY UPDATE`
  # serializes these writers without blocking inserts that reference the user,
  # and the lock timeout bounds the wait behind the user's other row lockers.
  defp locked(user, fun) do
    fn ->
      Repo.query!("SET LOCAL lock_timeout = '5s'")

      case Repo.one(from u in User, where: u.id == ^user.id, select: u.id, lock: "FOR NO KEY UPDATE") do
        nil -> {:error, :not_found}
        _id -> fun.()
      end
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
