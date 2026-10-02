defmodule TuistEx.Analytics.MachineMetrics do
  @moduledoc false

  # Periodically samples CPU utilization, memory usage, and network and disk
  # throughput while a build or test run is in flight, mirroring what the
  # Xcode command-line tool and the Gradle plugin submit. CPU and memory come
  # from Erlang's `:os_mon` applications (`:cpu_sup`, `:memsup`); network and
  # disk are bytes per second, derived from the machine-wide counters in
  # `IOCounters` between one sample and the next. A counter that cannot be
  # read on this platform is reported as zero.
  #
  # The sampler is a `GenServer` started next to `CompileReporter`; it emits
  # samples via `record/1` on the given collector process and shuts down when
  # `stop/1` is called. Consumers own the collector state.

  use GenServer

  alias TuistEx.Analytics.IOCounters

  # Started on demand (see ensure_os_mon_started/0), so not a declared dependency.
  @compile {:no_warn_undefined, [:cpu_sup, :memsup]}

  @default_interval_ms 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def stop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    :ok
  end

  @doc """
  Returns a sample map with the fields the server persists. `rates` carries
  the network and disk throughput since the previous sample (see `rates/3`).
  """
  def sample(now_fn \\ &os_time_seconds/0, rates \\ %{}) do
    Map.merge(
      %{
        timestamp: now_fn.(),
        cpu_usage_percent: cpu_usage_percent(),
        memory_used_bytes: memory_used_bytes(),
        memory_total_bytes: memory_total_bytes(),
        network_bytes_in: 0,
        network_bytes_out: 0,
        disk_bytes_read: 0,
        disk_bytes_written: 0
      },
      rates
    )
  end

  @doc """
  Bytes per second between two `IOCounters.read/0` readings taken
  `elapsed_ms` apart. A counter missing from either reading, or one that went
  backwards (a device was removed), counts as no throughput.
  """
  def rates(previous, current, elapsed_ms) do
    {network_in, network_out} = rate(previous.network, current.network, elapsed_ms)
    {disk_read, disk_written} = rate(previous.disk, current.disk, elapsed_ms)

    %{
      network_bytes_in: network_in,
      network_bytes_out: network_out,
      disk_bytes_read: disk_read,
      disk_bytes_written: disk_written
    }
  end

  defp rate({previous_a, previous_b}, {current_a, current_b}, elapsed_ms) when elapsed_ms > 0 do
    {div(max(current_a - previous_a, 0) * 1000, elapsed_ms),
     div(max(current_b - previous_b, 0) * 1000, elapsed_ms)}
  end

  defp rate(_previous, _current, _elapsed_ms), do: {0, 0}

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      started_os_mon?: ensure_os_mon_started(),
      sink: Keyword.fetch!(opts, :sink),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      counters: %{network: nil, disk: nil},
      counters_at: System.monotonic_time(:millisecond)
    }

    {:ok, state, {:continue, :first_sample}}
  end

  # Sample once at the start, so a build shorter than the interval still has
  # a reading. It carries no throughput: that needs two counter readings.
  # Done after init so reading the counters never delays the build.
  @impl true
  def handle_continue(:first_sample, state) do
    counters = IOCounters.read()
    apply_sink(state.sink, sample())
    schedule_sample(state.interval_ms)
    {:noreply, %{state | counters: counters, counters_at: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_info(:sample, state) do
    counters = IOCounters.read()
    now = System.monotonic_time(:millisecond)

    apply_sink(
      state.sink,
      sample(&os_time_seconds/0, rates(state.counters, counters, now - state.counters_at))
    )

    schedule_sample(state.interval_ms)
    {:noreply, %{state | counters: counters, counters_at: now}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Shut the monitor's port programs down with the sampler; left running,
  # they print "Erlang has closed" when the VM exits. Only when this sampler
  # is the one that started the monitor.
  @impl true
  def terminate(_reason, %{started_os_mon?: true}) do
    for child <- [:cpu_sup, :memsup], do: :supervisor.terminate_child(:os_mon_sup, child)
    :ok
  catch
    _, _ -> :ok
  end

  def terminate(_reason, _state), do: :ok

  defp schedule_sample(interval_ms), do: Process.send_after(self(), :sample, interval_ms)

  defp apply_sink(sink, sample) when is_function(sink, 1), do: sink.(sample)

  defp apply_sink(pid, sample) when is_pid(pid), do: send(pid, {:machine_metric, sample})
  defp apply_sink(_sink, _sample), do: :ok

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

  defp memory_used_bytes, do: used_memory_bytes(memory_data())

  # Free memory excludes the file cache, which the system gives back on
  # demand, so "total minus free" sits near the total on any machine that has
  # been running for a while. Available memory accounts for that; fall back
  # to free memory only where the platform does not report it.
  @doc false
  def used_memory_bytes(data) do
    total = Keyword.get(data, :total_memory, 0)
    unused = Keyword.get(data, :available_memory) || Keyword.get(data, :free_memory, 0)
    max(total - unused, 0)
  end

  defp memory_total_bytes, do: Keyword.get(memory_data(), :total_memory, 0)

  defp memory_data do
    :memsup.get_system_memory_data()
  rescue
    _ -> []
  catch
    _, _ -> []
  end

  # The OS monitor is started on demand rather than declared as a dependency,
  # so it never boots inside the host application. Its disk monitor is turned
  # off: it would log "disk almost full" alarms into the user's terminal.
  defp ensure_os_mon_started do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :ensure_application!, 1) do
      Mix.ensure_application!(:os_mon)
    end

    Application.put_env(:os_mon, :start_disksup, false)
    Application.put_env(:os_mon, :start_os_sup, false)

    case Application.ensure_all_started(:os_mon) do
      {:ok, started} -> :os_mon in started
      _ -> false
    end
  rescue
    _ -> false
  end

  defp os_time_seconds, do: :os.system_time(:millisecond) / 1_000
end
