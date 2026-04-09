defmodule Cache.Gradle.EventsPipeline do
  @moduledoc """
  Broadway pipeline for batching and sending Gradle cache events to the server.

  Events are sent to the gradle-cache webhook endpoint.
  """
  use Broadway

  alias Broadway.Message

  def start_link(_opts) do
    batch_size = Application.get_env(:cache, :events_batch_size, 100)
    batch_timeout = Application.get_env(:cache, :events_batch_timeout, 5_000)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {OffBroadwayMemory.Producer, buffer: :gradle_events_buffer},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 2]
      ],
      batchers: [
        http: [
          concurrency: 2,
          batch_size: batch_size,
          batch_timeout: batch_timeout
        ]
      ]
    )
  end

  @doc """
  Pushes a Gradle cache event to the pipeline asynchronously.
  """
  def async_push(event) do
    OffBroadwayMemory.Buffer.async_push(:gradle_events_buffer, event)
  end

  @impl true
  def handle_message(_processor, message, _context) do
    message
    |> Message.put_batch_key(:default)
    |> Message.put_batcher(:http)
  end

  @impl true
  def handle_batch(:http, messages, _batch_info, _context) do
    events = Enum.map(messages, & &1.data)
    send_batch(events)
    messages
  end

  defp send_batch(events) do
    server_url = Cache.Authentication.server_url()
    url = "#{server_url}/webhooks/gradle-cache"

    api_events =
      Enum.map(events, fn event ->
        %{
          account_handle: event.account_handle,
          project_handle: event.project_handle,
          action: event.action,
          size: event.size,
          cache_key: event.cache_key
        }
      end)

    body = JSON.encode!(%{events: api_events})

    Cache.WebhookClient.signed_post(url, body, "Gradle cache analytics")
  end
end
