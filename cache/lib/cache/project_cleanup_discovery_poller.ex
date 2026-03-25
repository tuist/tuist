defmodule Cache.ProjectCleanupDiscoveryPoller do
  @moduledoc false

  use GenServer

  alias Cache.ApplyProjectCleanupWorker
  alias Cache.Config
  alias Cache.DistributedKV.Cleanup

  require Logger

  @page_size 100
  @oban_retry_interval_ms 1_000

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
    case poll_once(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason, new_state} -> {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_info(:poll, state) do
    {new_state, next_interval_ms} =
      case poll_once(state) do
        {:ok, new_state} ->
          {new_state, Config.distributed_kv_cleanup_discovery_interval_ms()}

        {:error, :oban_not_ready, new_state} ->
          {new_state, @oban_retry_interval_ms}

        {:error, %{account_handle: account_handle, project_handle: project_handle, changeset: changeset}, new_state} ->
          Logger.error(
            "Failed to enqueue apply cleanup job for #{account_handle}/#{project_handle}: #{inspect(changeset)}"
          )

          {new_state, Config.distributed_kv_cleanup_discovery_interval_ms()}
      end

    schedule_poll(next_interval_ms)
    {:noreply, new_state}
  end

  defp poll_once(state) do
    {events, next_watermark} = Cleanup.list_published_cleanups_after_event_id(state.watermark, @page_size)

    case enqueue_apply_jobs(events) do
      :ok ->
        if events == [] do
          {:ok, state}
        else
          :ok = Cleanup.put_local_discovery_watermark(next_watermark)
          {:ok, %{state | watermark: next_watermark}}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp enqueue_apply_jobs(events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case enqueue_apply_job(event) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp enqueue_apply_job(event) do
    cutoff_iso = DateTime.to_iso8601(event.published_cleanup_cutoff_at)

    changeset =
      ApplyProjectCleanupWorker.new(%{
        account_handle: event.account_handle,
        project_handle: event.project_handle,
        generation: event.published_cleanup_generation,
        cutoff: cutoff_iso
      })

    if oban_ready?() do
      case Oban.insert(changeset) do
        {:ok, _job} ->
          :ok

        {:error, changeset} ->
          {:error, %{account_handle: event.account_handle, project_handle: event.project_handle, changeset: changeset}}
      end
    else
      {:error, :oban_not_ready}
    end
  end

  defp oban_ready? do
    Process.whereis(Oban.Registry) != nil and Registry.lookup(Oban.Registry, Oban) != []
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end
end
