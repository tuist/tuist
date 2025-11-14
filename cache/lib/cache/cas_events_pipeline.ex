defmodule Cache.CasEventsPipeline do
  @moduledoc """
  Broadway pipeline for batching and sending CAS events to the server.

  Events are batched by project (account_handle/project_handle pair) and sent
  to the appropriate endpoint.
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
    # Batch by project (account_handle/project_handle pair)
    %{account_handle: account_handle, project_handle: project_handle} = message.data

    message
    |> Message.put_batch_key({account_handle, project_handle})
    |> Message.put_batcher(:http)
  end

  @impl true
  def handle_batch(:http, messages, %{batch_key: {account_handle, project_handle}}, _context) do
    events = Enum.map(messages, & &1.data)
    send_batch(account_handle, project_handle, events)
    messages
  end

  defp send_batch(account_handle, project_handle, events) do
    server_url = Cache.Authentication.server_url()
    cas_config = Application.get_env(:cache, :cas, [])
    secret = Keyword.fetch!(cas_config, :api_key)
    url = "#{server_url}/api/projects/#{account_handle}/#{project_handle}/cache/cas/events"

    # Transform events to the format expected by the API
    api_events =
      Enum.map(events, fn event ->
        %{
          action: event.action,
          size: event.size,
          cas_id: event.cas_id
        }
      end)

    body = Jason.encode!(%{events: api_events})
    Logger.info("Secret nil or not: #{is_nil(secret)}")
    Logger.info("The secret length: #{byte_size(secret)}")

    signature =
      :hmac
      |> :crypto.mac(:sha256, secret, body)
      |> Base.encode16(case: :lower)

    headers = [
      {"x-signature", signature},
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
