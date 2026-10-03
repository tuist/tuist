defmodule Atlas.GTM.Workers.DeliverAutomatedEmail do
  @moduledoc false

  use Oban.Worker, queue: :mailing, max_attempts: 5, unique: [period: :infinity, fields: [:args]]

  alias Atlas.GTM.Broadcasts
  alias Atlas.GTM.Email
  alias Atlas.GTM.Subscriptions
  alias Atlas.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}}) do
    case Subscriptions.get_delivery(delivery_id) do
      nil ->
        {:cancel, :delivery_not_found}

      %{status: "delivered", kind: "welcome", subscriber: subscriber} ->
        Subscriptions.mark_welcomed(subscriber)
        :ok

      %{status: "delivered"} ->
        :ok

      delivery ->
        deliver(delivery)
    end
  end

  defp deliver(%{kind: "confirmation"} = delivery) do
    deliver_email(delivery, Email.confirmation(delivery, Subscriptions.confirmation_url(delivery)))
  end

  defp deliver(%{kind: "welcome"} = delivery) do
    unsubscribe_url = Subscriptions.unsubscribe_url(delivery.audience, delivery.subscriber)

    case deliver_email(delivery, Email.welcome(delivery, unsubscribe_url)) do
      :ok ->
        Subscriptions.mark_welcomed(delivery.subscriber)
        :ok

      error ->
        error
    end
  end

  defp deliver(%{kind: "transactional"} = delivery) do
    case Email.transactional(delivery) do
      {:error, reason} -> {:cancel, reason}
      email -> deliver_email(delivery, email)
    end
  end

  defp deliver(delivery), do: {:cancel, {:unsupported_delivery_kind, delivery.kind}}

  defp deliver_email(delivery, email) do
    case Mailer.deliver(email) do
      {:ok, response} ->
        {:ok, _delivery} =
          Broadcasts.update_delivery(delivery, %{
            status: "delivered",
            provider_message_id: provider_message_id(response),
            error: nil,
            delivered_at: timestamp()
          })

        :ok

      {:error, reason} ->
        Broadcasts.update_delivery(delivery, %{status: "failed", error: inspect(reason)})
        {:error, reason}
    end
  end

  defp provider_message_id(%{id: id}) when is_binary(id), do: id
  defp provider_message_id(%{"id" => id}) when is_binary(id), do: id
  defp provider_message_id(_response), do: nil

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
