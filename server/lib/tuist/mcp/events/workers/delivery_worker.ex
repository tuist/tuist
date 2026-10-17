defmodule Tuist.MCP.Events.Workers.DeliveryWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :mcp_events,
    max_attempts: 7

  import Ecto.Query

  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.SubscriptionAuthorization
  alias Tuist.Repo

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(second: 10)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subscription_id" => id, "event_id" => event_id, "body" => body}}) do
    case Repo.get(Subscription, id) do
      nil ->
        :ok

      subscription ->
        if SubscriptionAuthorization.authorized?(subscription) do
          deliver(subscription, event_id, body)
        else
          delete_subscription(subscription.id)
          :ok
        end
    end
  end

  defp deliver(subscription, event_id, body) do
    encoded = JSON.encode!(body)

    if byte_size(encoded) > 262_144 do
      {:discard, :payload_too_large}
    else
      result = Callback.post(subscription.callback_url, subscription.signing_secret, subscription.id, event_id, encoded)
      handle_response(result, subscription)
    end
  end

  defp handle_response({:ok, %{status: status}}, subscription) when status in 200..299 do
    reset_timeouts(subscription.id)
    :ok
  end

  defp handle_response({:ok, %{status: 410}}, subscription), do: delete_subscription(subscription.id)
  defp handle_response({:ok, %{status: 413}}, _subscription), do: {:discard, :payload_rejected}
  defp handle_response({:ok, %{status: status}}, _subscription), do: {:error, {:callback_status, status}}
  defp handle_response({:error, :timeout}, subscription), do: handle_timeout(subscription.id)
  defp handle_response({:error, :overloaded}, _subscription), do: {:snooze, 5}
  defp handle_response({:error, :invalid_callback_url}, _subscription), do: {:discard, :invalid_callback_url}
  defp handle_response({:error, reason}, _subscription), do: {:error, reason}

  defp handle_timeout(id) do
    query =
      from s in Subscription,
        where: s.id == ^id,
        select: {s.consecutive_timeouts, s.first_timeout_at},
        update: [
          inc: [consecutive_timeouts: 1],
          set: [first_timeout_at: fragment("COALESCE(first_timeout_at, CURRENT_TIMESTAMP)")]
        ]

    {_, attempts} = Repo.update_all(query, [])

    now = DateTime.utc_now()

    if Enum.any?(attempts, fn {count, first_at} ->
         count >= 3 and DateTime.diff(now, first_at, :second) >= 300
       end) do
      delete_subscription(id)
    else
      {:error, :timeout}
    end
  end

  defp reset_timeouts(id) do
    Repo.update_all(from(s in Subscription, where: s.id == ^id),
      set: [consecutive_timeouts: 0, first_timeout_at: nil]
    )
  end

  defp delete_subscription(id) do
    Repo.delete_all(from s in Subscription, where: s.id == ^id)
    :ok
  end
end
