defmodule Atlas.GTM.Workers.DeliverBroadcast do
  @moduledoc false

  use Oban.Worker, queue: :mailing, max_attempts: 5, unique: [period: :infinity, fields: [:args]]

  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Broadcasts
  alias Atlas.GTM.Email
  alias Atlas.GTM.Subscriptions
  alias Atlas.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"broadcast_id" => broadcast_id}}) do
    case Broadcasts.get_broadcast(broadcast_id) do
      nil ->
        {:cancel, :broadcast_not_found}

      broadcast ->
        {:ok, broadcast} = Broadcasts.mark_sending(broadcast)

        broadcast
        |> Broadcasts.list_pending_deliveries()
        |> Task.async_stream(&deliver(broadcast, &1), timeout: :infinity, max_concurrency: delivery_concurrency())
        |> Stream.run()

        {:ok, broadcast} = Broadcasts.finalize(broadcast)

        if broadcast.status == "sent", do: :ok, else: {:error, :one_or_more_deliveries_failed}
    end
  end

  defp deliver(broadcast, delivery) do
    subscriber = delivery.subscriber

    if subscriber && subscriber.status == "subscribed" && Audiences.subscribed?(broadcast.audience, subscriber) do
      unsubscribe_url = Subscriptions.unsubscribe_url(broadcast.audience, subscriber)
      email = Email.broadcast(broadcast, delivery, unsubscribe_url)

      case Mailer.deliver(email) do
        {:ok, response} ->
          Broadcasts.update_delivery(delivery, %{
            status: "delivered",
            provider_message_id: provider_message_id(response),
            error: nil,
            delivered_at: timestamp()
          })

        {:error, reason} ->
          Broadcasts.update_delivery(delivery, %{status: "failed", error: inspect(reason)})
      end
    else
      Broadcasts.update_delivery(delivery, %{status: "skipped", error: "subscriber is no longer subscribed"})
    end
  end

  defp provider_message_id(%{id: id}) when is_binary(id), do: id
  defp provider_message_id(%{"id" => id}) when is_binary(id), do: id
  defp provider_message_id(_response), do: nil

  defp delivery_concurrency do
    Application.get_env(:atlas, :gtm_email, [])
    |> Keyword.get(:delivery_concurrency, 5)
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
