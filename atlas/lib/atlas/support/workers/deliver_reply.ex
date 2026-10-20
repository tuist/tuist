defmodule Atlas.Support.Workers.DeliverReply do
  use Oban.Worker, queue: :mailing, max_attempts: 5, unique: [period: :infinity, fields: [:args]]

  alias Atlas.Support

  def enqueue(message_id) when is_binary(message_id) do
    %{"message_id" => message_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) when is_binary(message_id) do
    case Support.deliver_reply(message_id) do
      :ok -> :ok
      {:cancel, reason} -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: {:cancel, :missing_message_id}
end
