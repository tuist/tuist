defmodule Cache.AnalyticsPipeline do
  @moduledoc """
  Broadway pipeline for batching and sending CAS analytics events to the server.

  Events are batched by project (account_handle/project_handle pair) and sent
  to the appropriate endpoint.
  """
  use Broadway

  alias Broadway.Message

  require Logger

  def start_link(_opts) do
    batch_size = Application.get_env(:cache, :analytics_batch_size, 100)
    batch_timeout = Application.get_env(:cache, :analytics_batch_timeout, 5_000)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {producer_module(), producer_options()},
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

  defp producer_module do
    Application.get_env(:cache, :analytics_pipeline_producer_module, OffBroadwayMemory.Producer)
  end

  defp producer_options do
    Application.get_env(:cache, :analytics_pipeline_producer_options,
      buffer: :analytics_buffer
    )
  end

  @doc """
  Pushes an analytics event to the pipeline asynchronously.
  """
  def async_push(event) do
    buffer = Keyword.fetch!(producer_options(), :buffer)
    OffBroadwayMemory.Buffer.async_push(buffer, event)
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
    cond do
      not analytics_enabled?() ->
        Logger.debug("CAS analytics disabled, skipping batch of #{length(events)} events")
        :ok

      is_nil(Cache.Authentication.server_url()) ->
        Logger.warning("No server URL configured for CAS analytics")
        :ok

      true ->
        do_send_batch(account_handle, project_handle, events)
    end
  end

  defp do_send_batch(account_handle, project_handle, events) do
    server_url = Cache.Authentication.server_url()

    url = "#{server_url}/api/projects/#{account_handle}/#{project_handle}/cache/cas/events"

    # Get auth header from first event (all events in batch have same auth)
    auth_header = List.first(events).auth_header || ""

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

    headers = [
      {"authorization", auth_header},
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
        Logger.debug(
          "Successfully sent #{length(events)} CAS analytics events for #{account_handle}/#{project_handle}"
        )

        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "Failed to send CAS analytics (status #{status}): #{inspect(body)}"
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to send CAS analytics: #{inspect(reason)}")
        :ok
    end
  end

  defp analytics_enabled?() do
    Application.get_env(:cache, :analytics_enabled, true)
  end
end
