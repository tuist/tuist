defmodule TuistEx.Analytics.MachineMetrics do
  @moduledoc false

  # Periodically samples CPU utilization and memory usage while a build or
  # test run is in flight, mirroring what the Xcode command-line tool and
  # the Gradle plugin submit. Uses Erlang's `:os_mon` applications
  # (`:cpu_sup`, `:memsup`), which cover macOS and Linux; network and disk
  # rates aren't available through a portable Erlang API, so they're
  # reported as zero for now.
  #
  # The sampler is a `GenServer` started next to `CompileReporter`; it emits
  # samples via `record/1` on the given collector process and shuts down when
  # `stop/1` is called. Consumers own the collector state.

  use GenServer

  @default_interval_ms 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def stop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    :ok
  end

  @doc "Returns a sample map with the fields the server persists."
  def sample(now_fn \\ &os_time_seconds/0) do
    %{
      timestamp: now_fn.(),
      cpu_usage_percent: cpu_usage_percent(),
      memory_used_bytes: memory_used_bytes(),
      memory_total_bytes: memory_total_bytes(),
      network_bytes_in: 0,
      network_bytes_out: 0,
      disk_bytes_read: 0,
      disk_bytes_written: 0
    }
  end

  @impl true
  def init(opts) do
    ensure_os_mon_started()

    state = %{
      sink: Keyword.fetch!(opts, :sink),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms)
    }

    schedule_sample(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:sample, state) do
    apply_sink(state.sink, sample())
    schedule_sample(state.interval_ms)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule_sample(interval_ms), do: Process.send_after(self(), :sample, interval_ms)

  defp apply_sink(sink, sample) when is_function(sink, 1), do: sink.(sample)

  defp apply_sink(pid, sample) when is_pid(pid), do: send(pid, {:machine_metric, sample})

  defp cpu_usage_percent do
    case :cpu_sup.util() do
      value when is_number(value) -> value * 1.0
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  catch
    _, _ -> 0.0
  end

  defp memory_used_bytes do
    data = memory_data()
    total = Keyword.get(data, :total_memory, 0)
    free = Keyword.get(data, :free_memory, 0)
    max(total - free, 0)
  end

  defp memory_total_bytes, do: Keyword.get(memory_data(), :total_memory, 0)

  defp memory_data do
    :memsup.get_system_memory_data()
  rescue
    _ -> []
  catch
    _, _ -> []
  end

  defp ensure_os_mon_started do
    _ = Application.ensure_all_started(:os_mon)
    :ok
  end

  defp os_time_seconds, do: :os.system_time(:millisecond) / 1_000
end
