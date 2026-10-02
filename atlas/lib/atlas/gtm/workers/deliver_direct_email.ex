defmodule Atlas.GTM.Workers.DeliverDirectEmail do
  @moduledoc """
  Delivers one direct, per-recipient transactional email.

  Unlike `Atlas.GTM.Workers.DeliverBroadcast` this never consults subscriber
  status or audience membership: the recipient is entitled to the notice, so
  there is nothing to skip on.
  """

  use Oban.Worker, queue: :mailing, max_attempts: 5, unique: [period: :infinity, fields: [:args]]

  alias Atlas.GTM.Broadcasts
  alias Atlas.GTM.DirectEmails
  alias Atlas.GTM.Email
  alias Atlas.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}}) do
    case DirectEmails.get_delivery(delivery_id) do
      nil -> {:cancel, :delivery_not_found}
      %{status: "delivered"} -> :ok
      delivery -> deliver(delivery)
    end
  end

  defp deliver(delivery) do
    case Mailer.deliver(Email.direct(delivery)) do
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
