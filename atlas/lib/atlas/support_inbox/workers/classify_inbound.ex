defmodule Atlas.SupportInbox.Workers.ClassifyInbound do
  @moduledoc """
  Runs the inbound-email classifier for a freshly ingested support
  message, persists the decision onto the thread, and enqueues the
  Slack notification. This is the first step of the inbound
  pipeline; `Atlas.Support.Workers.PostNotification` remains
  responsible for the actual Slack post and reads the persisted
  classification off the thread.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :args]]

  alias Atlas.Support
  alias Atlas.SupportInbox.Classifier

  def enqueue(thread_id, message_id) when is_binary(thread_id) and is_binary(message_id) do
    %{"thread_id" => thread_id, "message_id" => message_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    thread_id = args["thread_id"]
    message_id = args["message_id"]

    with thread when not is_nil(thread) <- Support.get_thread(thread_id),
         message when not is_nil(message) <- Support.get_message(message_id),
         {:ok, _decision} <- Classifier.classify_and_persist(thread, message) do
      :ok
    else
      nil ->
        {:cancel, :support_thread_or_message_not_found}

      {:error, _reason} = error ->
        error
    end
  end
end
