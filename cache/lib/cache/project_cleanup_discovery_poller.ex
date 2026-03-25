defmodule Cache.ProjectCleanupDiscoveryPoller do
  @moduledoc false

  use GenServer

  alias Cache.ApplyProjectCleanupWorker
  alias Cache.Config
  alias Cache.DistributedKV.Cleanup

  require Logger

  @page_size 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def poll_now do
    GenServer.call(__MODULE__, :poll, :infinity)
  end

  @impl true
  def init(_opts) do
    schedule_poll(0)
    {:ok, %{watermark: Cleanup.get_local_discovery_watermark()}}
  end

  @impl true
  def handle_call(:poll, _from, state) do
    new_state = poll_once(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = poll_once(state)
    schedule_poll(Config.distributed_kv_cleanup_discovery_interval_ms())
    {:noreply, new_state}
  end

  defp poll_once(state) do
    {events, next_watermark} = Cleanup.list_published_cleanups_after_event_id(state.watermark, @page_size)

    Enum.each(events, fn event ->
      :ok = enqueue_apply_job(event)
    end)

    if events != [] do
      :ok = Cleanup.put_local_discovery_watermark(next_watermark)
    end

    %{state | watermark: next_watermark}
  end

  defp enqueue_apply_job(event) do
    cutoff_iso = DateTime.to_iso8601(event.published_cleanup_cutoff_at)

    %{
      account_handle: event.account_handle,
      project_handle: event.project_handle,
      generation: event.published_cleanup_generation,
      cutoff: cutoff_iso
    }
    |> ApplyProjectCleanupWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, changeset} ->
        Logger.warning(
          "Failed to enqueue apply cleanup job for #{event.account_handle}/#{event.project_handle}: #{inspect(changeset)}"
        )

        :ok
    end
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end
end
