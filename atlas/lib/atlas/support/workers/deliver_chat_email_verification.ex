defmodule Atlas.Support.Workers.DeliverChatEmailVerification do
  @moduledoc false

  use Oban.Worker, queue: :mailing, max_attempts: 5, unique: [period: :infinity, fields: [:args]]

  alias Atlas.Support

  def enqueue(thread_id) when is_binary(thread_id) do
    %{"thread_id" => thread_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => thread_id}}) when is_binary(thread_id) do
    case Support.deliver_chat_email_verification(thread_id) do
      :ok -> :ok
      {:cancel, reason} -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: {:cancel, :missing_thread_id}
end
