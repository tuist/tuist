defmodule Atlas.Inbox.Workers.IngestEmail do
  @moduledoc """
  Processes a persisted inbound email asynchronously so the request path stays
  fast and transient upstream failures (OpenAI 5xx, network blips) get retried
  instead of dropping the message.

  Default Oban backoff over five attempts spans roughly 17 minutes, which is
  long enough to ride out a typical provider hiccup without holding mail in
  limbo forever.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Atlas.Inbox
  alias Atlas.LLMs.Errors, as: LLMErrors

  def enqueue(inbox_email_id) when is_binary(inbox_email_id) do
    %{"inbox_email_id" => inbox_email_id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"inbox_email_id" => inbox_email_id}}) when is_binary(inbox_email_id) do
    case Inbox.process_inbound(inbox_email_id) do
      {:ok, _outcome} -> :ok
      {:ignored, _reason} -> :ok
      {:cancel, reason} -> {:cancel, reason}
      {:error, reason} -> LLMErrors.oban_error(reason)
    end
  end

  def perform(%Oban.Job{}), do: {:cancel, :missing_inbox_email_id}
end
