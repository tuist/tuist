defmodule Tuist.Analytics.Posthog do
  @moduledoc """
  A gen server that sends analytics events to PostHog.
  The gen server uses ETS to store the events and sends them in batches every 10 seconds.
  """
  use GenServer, shutdown: 2_000

  require Logger

  @default_publish_interval 10_000
  @handler_id "analytics-posthog"

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(_opts) do
    name = "Posthog"
    table_id = create_table(String.to_atom("#{name}.Ets"))

    Process.flag(:trap_exit, true)
    attach(table_id)
    Logger.info("#{name} Started")

    {:ok, {name, table_id}, @default_publish_interval}
  end

  @impl GenServer
  def terminate(reason, {name, table_id}) do
    Logger.warning("[#{name}] Stopped with reason #{inspect(reason)}")
    detach()

    Logger.info("[#{name}] Flushing final events to Posthog")
    events = :ets.select(table_id, [{{:"$1", :"$2"}, [], [:"$2"]}])

    if length(events) > 0 do
      case capture_batch(events) do
        {:ok, _} -> Logger.info("[#{name}] Final events flushed to Posthog")
        {:error, _} -> Logger.error("[#{name}] Failed to flush final events to Posthog")
      end
    end

    :ets.delete(table_id)
  end

  def attach(table_id) do
    :telemetry.attach_many(
      @handler_id,
      events(),
      &__MODULE__.handle_event/4,
      %{table_id: table_id}
    )
  end

  defp events do
    Enum.reject(Tuist.Analytics.all_events(), fn event ->
      # We send many of these events so it's expensive.
      event == [:analytics, :cache_artifact, :upload] or
        event == [:analytics, :cache_artifact, :download]
    end)
  end

  def detach do
    :telemetry.detach(@handler_id)
  end

  @impl GenServer
  def handle_info(:timeout, {name, table_id} = state) do
    Logger.debug("[#{name}] Flushing events to Posthog")
    now = DateTime.to_unix(DateTime.utc_now(), :millisecond)

    events = :ets.select(table_id, [{{:"$1", :"$2"}, [{:<, :"$1", now}], [:"$2"]}])

    if length(events) > 0 do
      case capture_batch(events) do
        {:ok, _} ->
          :ets.select_delete(table_id, [{{:"$1", :"$2"}, [{:<, :"$1", now}], [true]}])

        {:error, error} ->
          Logger.error("[#{name}] Failed to flush events to Posthog: #{inspect(error)}")
      end
    end

    {:noreply, state, @default_publish_interval}
  end

  def handle_event([:analytics | event_id], measurements, metadata, config) do
    table_id = config[:table_id]
    date = DateTime.utc_now()

    {user_id, metadata} = Map.pop(metadata, :user_id)
    {project_id, metadata} = Map.pop(metadata, :project_id)

    distinct_id_params =
      cond do
        not is_nil(user_id) -> %{distinct_id: "user_#{user_id}"}
        not is_nil(project_id) -> %{distinct_id: "project_#{user_id}"}
        true -> %{}
      end

    event_name = Enum.map_join(event_id, "_", &Atom.to_string/1)

    event =
      Map.merge(
        %{
          event: event_name,
          properties: Map.merge(metadata, measurements),
          timestamp: DateTime.to_iso8601(date)
        },
        distinct_id_params
      )

    :ets.insert(
      table_id,
      {DateTime.to_unix(date, :millisecond), event}
    )

    :ok
  end

  def capture_batch(entries) do
    body = %{batch: entries, api_key: Tuist.Environment.posthog_api_key()}

    base_request()
    |> Req.post(
      url: "/capture",
      json: body,
      headers: [{"Content-Type", "application/json"}],
      finch: Tuist.Finch
    )
    |> transform_response()
  end

  defp transform_response({:ok, %{status: status} = response}) when status >= 400 do
    {:error, response}
  end

  defp transform_response(response), do: response

  defp base_request do
    Req.new(base_url: Tuist.Environment.posthog_url(), finch: Tuist.Finch)
  end

  defp create_table(name) do
    :ets.new(name, [:named_table, :duplicate_bag, :public, {:write_concurrency, true}])
  end
end
