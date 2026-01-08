defmodule Cache.CASEventsPipeline do
  @moduledoc """
  Broadway pipeline for batching and sending CAS events to the server.

  Events are sent to the cache webhook endpoint.
  """
  use Broadway

  alias Broadway.Message

  require Logger

  def start_link(_opts) do
    cas_config = Application.get_env(:cache, :cas, [])
    batch_size = Keyword.get(cas_config, :events_batch_size, 100)
    batch_timeout = Keyword.get(cas_config, :events_batch_timeout, 5_000)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {OffBroadwayMemory.Producer, buffer: :cas_events_buffer},
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
  Pushes a CAS event to the pipeline asynchronously.
  """
  def async_push(event) do
    OffBroadwayMemory.Buffer.async_push(:cas_events_buffer, event)
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
    case Cache.Config.api_key() do
      nil -> :ok
      secret -> do_send_batch(secret, events)
    end
  end

  defp do_send_batch(secret, events) do
    server_url = Cache.Authentication.server_url()
    url = "#{server_url}/webhooks/cache"

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

    body = Jason.encode!(%{events: api_events})

    signature =
      :hmac
      |> :crypto.mac(:sha256, secret, body)
      |> Base.encode16(case: :lower)

    headers = [
      {"x-cache-signature", signature},
      {"content-type", "application/json"}
    ]

    req_options = Application.get_env(:cache, :req_options, [])

    options =
      Keyword.merge(
        [
          url: url,
          method: :post,
          headers: headers,
          body: body,
          finch: Cache.Finch,
          retry: false,
          cache: false
        ],
        req_options
      )

    case Req.request(options) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to send CAS analytics (status #{status}): #{inspect(body)}")

        :ok

      {:error, reason} ->
        Logger.error("Failed to send CAS analytics: #{inspect(reason)}")
        :ok
    end
  end
end
