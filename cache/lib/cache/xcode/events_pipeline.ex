defmodule Cache.Xcode.EventsPipeline do
  @moduledoc """
  Broadway pipeline for batching and sending Xcode cache events to the server.

  Events are sent to the cache webhook endpoint.
  """
  use Broadway

  alias Broadway.Message

  @buffer_name :xcode_events_buffer

  def buffer_name, do: @buffer_name

  def start_link(_opts) do
    batch_size = Application.get_env(:cache, :events_batch_size, 100)
    batch_timeout = Application.get_env(:cache, :events_batch_timeout, 5_000)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {OffBroadwayMemory.Producer, buffer: buffer_name()},
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
  Pushes a Xcode cache event to the pipeline asynchronously.
  """
  def async_push(event) do
    async_push(event, buffer_name())
  end

  def async_push(event, buffer_name) do
    if Cache.AnalyticsCircuitBreaker.accept_event?(webhook_url()) do
      OffBroadwayMemory.Buffer.async_push(buffer_name, event)
    else
      :ok
    end
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
    api_events =
      Enum.map(events, fn event ->
        %{
          account_handle: event.account_handle,
          project_handle: event.project_handle,
          action: event.action,
          size: event.size,
          cas_id: event.cas_id
        }
      end)

    body = JSON.encode!(%{events: api_events})

    Cache.WebhookClient.signed_post(webhook_url(), body, "Xcode cache analytics")
  end

  defp webhook_url do
    "#{Cache.Authentication.server_url()}/webhooks/cache"
  end
end
