defmodule Tuist.MCP.Events.Subscriptions do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Accounts.User
  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Catalog
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.SubscriptionAuthorization
  alias Tuist.Repo

  require Logger

  @default_ttl_ms 7 * 24 * 60 * 60 * 1_000
  @minimum_ttl_ms 60 * 60 * 1_000
  @maximum_ttl_ms 30 * 24 * 60 * 60 * 1_000
  @maximum_subscriptions_per_user 25

  def subscribe(conn, %{"name" => name, "arguments" => args, "delivery" => delivery} = params)
      when is_map(args) and is_map(delivery) do
    if Catalog.supported?(name),
      do: subscribe_supported(conn, params, name, args, delivery),
      else: {:error, -32_602, "Invalid event subscription"}
  end

  def subscribe(_conn, _params), do: {:error, -32_602, "Invalid event subscription"}

  defp subscribe_supported(conn, params, name, args, delivery) do
    with {:ok, user, credential, target} <- SubscriptionAuthorization.authorized_target(conn, name, args),
         %{"mode" => "webhook", "url" => url, "secret" => secret} when is_binary(url) <- delivery,
         true <- Callback.valid_secret?(secret),
         id = subscription_id(user.id, credential, url, name, target),
         true <- subscription_available?(user.id, id),
         :ok <- Callback.verify(url, secret, id) do
      ttl_ms = requested_ttl(params["ttlMs"])
      refresh_before = DateTime.utc_now() |> DateTime.add(ttl_ms, :millisecond) |> DateTime.truncate(:second)

      attrs =
        credential
        |> Map.merge(target)
        |> Map.merge(%{
          id: id,
          user_id: user.id,
          event_name: name,
          callback_url: url,
          signing_secret: secret,
          refresh_before: refresh_before
        })

      case save_subscription(attrs) do
        {:ok, :ok} ->
          {:ok,
           %{"id" => id, "refreshBefore" => DateTime.to_iso8601(refresh_before), "cursor" => nil, "truncated" => false}}

        {:error, :limit} ->
          {:error, -32_602, "Subscription limit reached"}

        {:error, {:changeset, changeset}} ->
          Logger.error("MCP event subscription could not be saved: #{inspect(changeset.errors)}")
          {:error, -32_603, "Subscription could not be saved"}
      end
    else
      {:error, reason} when reason in [:invalid_url, :timeout, :unreachable, :challenge_failed] ->
        {:error, -32_015, "Callback verification failed", %{"reason" => Atom.to_string(reason)}}

      _ ->
        {:error, -32_602, "Invalid or unauthorized event subscription"}
    end
  end

  def unsubscribe(conn, %{"name" => name, "arguments" => args, "delivery" => %{"url" => url}})
      when is_map(args) and is_binary(url) do
    if Catalog.supported?(name),
      do: unsubscribe_supported(conn, name, args, url),
      else: {:error, -32_602, "Invalid event subscription"}
  end

  def unsubscribe(_conn, _params), do: {:error, -32_602, "Invalid event subscription"}

  defp unsubscribe_supported(conn, name, args, url) do
    case SubscriptionAuthorization.authorized_target(conn, name, args) do
      {:ok, user, credential, target} ->
        id = subscription_id(user.id, credential, url, name, target)
        Repo.delete_all(from s in Subscription, where: s.id == ^id and s.user_id == ^user.id)
        {:ok, %{}}

      _ ->
        {:ok, %{}}
    end
  end

  defp subscription_available?(user_id, id) do
    now = DateTime.utc_now()

    Repo.exists?(from s in Subscription, where: s.id == ^id) or
      Repo.aggregate(from(s in Subscription, where: s.user_id == ^user_id and s.refresh_before > ^now), :count, :id) <
        @maximum_subscriptions_per_user
  end

  defp save_subscription(attrs) do
    Repo.transaction(fn ->
      Repo.one!(from user in User, where: user.id == ^attrs.user_id, select: user.id, lock: "FOR NO KEY UPDATE")

      if subscription_available?(attrs.user_id, attrs.id) do
        case %Subscription{}
             |> Subscription.changeset(attrs)
             |> Repo.insert(
               on_conflict: {:replace, [:signing_secret, :refresh_before, :updated_at]},
               conflict_target: :id
             ) do
          {:ok, _subscription} -> :ok
          {:error, changeset} -> Repo.rollback({:changeset, changeset})
        end
      else
        Repo.rollback(:limit)
      end
    end)
  end

  defp subscription_id(user_id, credential, url, event_name, target) do
    credential_id = credential[:oauth_grant_id] || credential[:account_token_id] || credential[:agent_registration_id]
    target_id = target[:project_id] || "account:#{target[:account_id]}"
    digest = :crypto.hash(:sha256, "#{user_id}:#{credential_id}:#{url}:#{event_name}:#{target_id}")
    "sub_" <> Base.url_encode64(digest, padding: false)
  end

  defp requested_ttl(ttl) when is_integer(ttl) and ttl > 0, do: ttl |> min(@maximum_ttl_ms) |> max(@minimum_ttl_ms)
  defp requested_ttl(_ttl), do: @default_ttl_ms
end
