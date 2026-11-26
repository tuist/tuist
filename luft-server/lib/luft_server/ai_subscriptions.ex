defmodule LuftServer.AISubscriptions do
  @moduledoc """
  A person's Claude and ChatGPT subscriptions, which Luft stores and runs
  threads on. Rows are keyed by the person's Tuist subject (`user_sub`).

  Claude connects with the subscription token `claude setup-token` prints.
  ChatGPT connects through OpenAI's device authorization
  (`LuftServer.AISubscriptions.ChatGPT`). Clients get metadata from `list/1`;
  only server-side inference code may call `credentials/2`, and its result
  must never be rendered, logged or serialized.

  State changes for one person serialize on a transaction-scoped advisory lock
  on their subject, but no lock or transaction is held while OpenAI is called.
  A poll or refresh claims its slot in a short locked step (`next_poll_at`,
  `refreshing_until`), calls OpenAI unlocked, and saves its result in a second
  locked step only if the row still holds the same sign-in or refresh token.
  A disconnect or cancel in between therefore wins, on any replica.

  Every open `ai_subscriptions` channel shows the current state: a change
  reaches the person's channels at once through `topic/1`.
  """

  import Ecto.Query

  alias LuftServer.AISubscriptions.ChatGPT
  alias LuftServer.AISubscriptions.Subscription
  alias LuftServer.Repo
  alias LuftServer.SignInLimit
  alias LuftServer.Threads.Provider

  @providers [:claude, :chatgpt]
  @login_lifetime 900
  @login_limit 5
  @login_window 300
  @refresh_margin 60
  # Longer than an OpenAI exchange can take (5s to connect, 15s to receive).
  @refresh_lease 30
  @refresh_wait_ms 25_000
  @refresh_wait_step_ms 200

  def providers, do: @providers

  def topic(%{user_sub: user_sub}), do: "ai_subscriptions:" <> user_sub

  @doc """
  Connection metadata for every provider, in display order, as clients see it.
  Never includes credentials.
  """
  def list(%{user_sub: user_sub}) when is_binary(user_sub) do
    connected =
      Repo.all(
        from s in Subscription,
          where: s.user_sub == ^user_sub and not is_nil(s.access_token),
          select: {s.provider, s.updated_at}
      )

    {:ok,
     Enum.map(@providers, fn provider ->
       updated_at = connected |> List.keyfind(provider, 0, {provider, nil}) |> elem(1)

       %{
         "provider" => Atom.to_string(provider),
         "connected" => not is_nil(updated_at),
         "updated_at" => updated_at && DateTime.to_iso8601(updated_at),
         "login_available" => provider == :claude or match?({:ok, _}, ChatGPT.client_id()),
         "runs_threads" => Provider.runs_threads?(Atom.to_string(provider))
       }
     end)}
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :storage_unavailable}
  end

  @doc "Tells the person's open channels what their subscriptions are now."
  def broadcast(session) do
    with {:ok, subscriptions} <- list(session) do
      Phoenix.PubSub.broadcast(
        LuftServer.PubSub,
        topic(session),
        {:ai_subscriptions, subscriptions}
      )

      {:ok, subscriptions}
    end
  end

  @doc """
  Saves a Claude subscription token from `claude setup-token`. This validates
  the token's format only; it does not prove the subscription can serve
  inference.
  """
  def connect_claude(%{user_sub: user_sub}, token) do
    if valid_claude_token?(token) do
      locked(user_sub, fn ->
        with {:ok, _} <-
               user_sub |> get_or_build(:claude) |> save(%{access_token: String.trim(token)}),
             do: :ok
      end)
    else
      {:error, :invalid_claude_token}
    end
  end

  @doc """
  Starts a ChatGPT device sign-in, replacing any sign-in still pending. Returns
  the opaque login ID to poll with and the code the person enters on OpenAI's
  verification page. At most five sign-ins start per person every 5 minutes.
  """
  def start_chatgpt(%{user_sub: user_sub}) do
    # Counted before OpenAI is called, and per person, so disconnecting
    # doesn't reset it. An unconfigured server counts nothing.
    with {:ok, _client_id} <- ChatGPT.client_id(),
         :ok <- SignInLimit.hit("chatgpt:" <> user_sub, @login_limit, @login_window),
         {:ok, login} <- ChatGPT.start() do
      login = Map.put(login, "id", Ecto.UUID.generate())

      locked(user_sub, fn ->
        with {:ok, saved} <-
               user_sub
               |> get_or_build(:chatgpt)
               |> save(%{
                 pending_login: Jason.encode!(login),
                 pending_expires_at: DateTime.add(now(), @login_lifetime, :second),
                 next_poll_at: DateTime.add(now(), login["interval"], :second)
               }) do
          {:ok,
           %{
             login_id: login["id"],
             user_code: login["user_code"],
             verification_url: login["verification_url"],
             interval: login["interval"],
             expires_at: DateTime.to_iso8601(saved.pending_expires_at)
           }}
        end
      end)
    end
  end

  @doc """
  Polls a ChatGPT sign-in. Returns `{:ok, :pending}` until the person approves
  the code (or until the upstream polling interval allows another request),
  then `{:ok, :connected}`. A sign-in cancelled, replaced or disconnected
  while OpenAI answered returns `{:error, :not_found}` and saves nothing.
  """
  def poll_chatgpt(%{user_sub: user_sub}, login_id) when is_binary(login_id) do
    with {:poll, login} <- claim_poll(user_sub, login_id) do
      result = ChatGPT.poll(login)
      locked(user_sub, fn -> finish_poll(user_sub, login, result) end)
    end
  end

  def poll_chatgpt(_session, _login_id), do: {:error, :not_found}

  defp claim_poll(user_sub, login_id) do
    locked(user_sub, fn ->
      with %Subscription{} = subscription <- get(user_sub, :chatgpt),
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
        with {:ok, _} <-
               save(subscription, %{
                 next_poll_at: DateTime.add(now(), login["interval"], :second)
               }),
             do: {:poll, login}
    end
  end

  defp finish_poll(user_sub, login, result) do
    with %Subscription{} = subscription <- get(user_sub, :chatgpt),
         {:ok, _login} <- pending_login(subscription, login["id"]) do
      save_poll_result(subscription, login, result)
    else
      _ -> {:error, :not_found}
    end
  end

  defp save_poll_result(subscription, login, {:ok, tokens}) do
    attrs =
      tokens
      |> Map.merge(cleared_login())
      |> Map.merge(%{client_id: login["client_id"], refreshing_until: nil})

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
  def cancel_chatgpt(%{user_sub: user_sub}, login_id) do
    locked(user_sub, fn ->
      with %Subscription{} = subscription <- get(user_sub, :chatgpt),
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
  authorization is not revoked; people revoke it at the provider.
  """
  def disconnect(%{user_sub: user_sub}, provider) when provider in @providers do
    locked(user_sub, fn ->
      Repo.delete_all(
        from s in Subscription, where: s.user_sub == ^user_sub and s.provider == ^provider
      )

      :ok
    end)
  end

  @doc """
  Server-side use only: a usable access token for the person's subscription
  to `provider`, refreshing an expiring ChatGPT token first. Concurrent
  callers share one refresh. Never render, log or serialize the result.
  """
  def credentials(user_sub, provider) when is_binary(user_sub) and provider in @providers,
    do: credentials(user_sub, provider, System.monotonic_time(:millisecond) + @refresh_wait_ms)

  defp credentials(user_sub, provider, deadline) do
    case claim_credentials(user_sub, provider) do
      {:refresh, refresh_token, client_id} ->
        result = ChatGPT.refresh(refresh_token, client_id)
        locked(user_sub, fn -> finish_refresh(user_sub, refresh_token, result) end)

      :wait ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(@refresh_wait_step_ms)
          credentials(user_sub, provider, deadline)
        else
          {:error, :chatgpt_refresh_failed}
        end

      result ->
        result
    end
  end

  defp claim_credentials(user_sub, provider) do
    locked(user_sub, fn ->
      case get(user_sub, provider) do
        %Subscription{provider: :chatgpt, access_token: token} = subscription
        when is_binary(token) ->
          claim_chatgpt_refresh(subscription)

        %Subscription{access_token: token} when is_binary(token) ->
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
        with {:ok, _} <-
               save(subscription, %{
                 refreshing_until: DateTime.add(now(), @refresh_lease, :second)
               }),
             do: {:refresh, subscription.refresh_token, subscription.client_id}
    end
  end

  defp finish_refresh(user_sub, refresh_token, result) do
    case get(user_sub, :chatgpt) do
      # Still the credentials this refresh started from.
      %Subscription{refresh_token: ^refresh_token} = subscription ->
        save_refresh(subscription, result)

      # Disconnected, or reconnected with new credentials, while OpenAI answered.
      %Subscription{access_token: token} = subscription when is_binary(token) ->
        if fresh?(subscription),
          do: {:ok, %{provider: :chatgpt, access_token: token}},
          else: {:error, :chatgpt_refresh_failed}

      _ ->
        {:error, :not_connected}
    end
  end

  defp save_refresh(subscription, {:ok, tokens}) do
    with {:ok, saved} <- save(subscription, Map.put(tokens, :refreshing_until, nil)) do
      {:ok, %{provider: :chatgpt, access_token: saved.access_token}}
    end
  end

  # OpenAI rejected the refresh token; the person has to sign in again.
  defp save_refresh(subscription, {:error, {:http_status, status}})
       when status in [400, 401, 403] do
    attrs = %{access_token: nil, refresh_token: nil, expires_at: nil, refreshing_until: nil}
    with {:ok, _} <- save(subscription, attrs), do: {:error, :reauthorization_required}
  end

  defp save_refresh(subscription, {:error, _reason}) do
    with {:ok, _} <- save(subscription, %{refreshing_until: nil}),
         do: {:error, :chatgpt_refresh_failed}
  end

  defp fresh?(%Subscription{expires_at: %DateTime{} = expires_at}),
    do: DateTime.after?(expires_at, DateTime.add(now(), @refresh_margin, :second))

  defp fresh?(_subscription), do: false

  defp pending_login(%Subscription{pending_login: pending}, login_id)
       when is_binary(pending) and is_binary(login_id) do
    case Jason.decode(pending) do
      {:ok, %{"id" => ^login_id} = login} -> {:ok, login}
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

  defp get(user_sub, provider),
    do: Repo.get_by(Subscription, user_sub: user_sub, provider: provider)

  defp get_or_build(user_sub, provider),
    do: get(user_sub, provider) || %Subscription{user_sub: user_sub, provider: provider}

  defp save(subscription, attrs) do
    case subscription |> Subscription.changeset(attrs) |> Repo.insert_or_update() do
      {:ok, saved} -> {:ok, saved}
      {:error, _changeset} -> {:error, :storage_unavailable}
    end
  end

  # Short transactions only: none of them calls OpenAI. The advisory lock is
  # per person and released at commit; the lock timeout bounds the wait.
  defp locked(user_sub, fun) do
    fn ->
      Repo.query!("SET LOCAL lock_timeout = '5s'", [], log: false)

      Repo.query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        ["ai-subscriptions:" <> user_sub],
        log: false
      )

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
