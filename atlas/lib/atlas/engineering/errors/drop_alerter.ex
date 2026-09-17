defmodule Atlas.Engineering.Errors.DropAlerter do
  @moduledoc """
  Out-of-band visibility for events dropped by the ingest pipeline.

  TODO(atlas): wire alerting. Hive posts to Slack + telemetry; Atlas has
  neither hooked up yet, so this port coalesces reports and periodically
  logs them via `Logger.warning/2`. The public API matches Hive's so
  callers (Errors, Event.Buffer) do not need to change once the real
  alert delivery lands.
  """

  use GenServer

  require Logger

  @flush_interval_ms :timer.seconds(60)
  @sample_limit 500

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def report_flush_failure(name, byte_size, exception) do
    GenServer.cast(
      __MODULE__,
      {:report, :flush_failure, %{name: inspect(name), byte_size: byte_size, sample: format_exception(exception)}}
    )
  end

  def report_ingest_failure(reason, sample_meta \\ %{}) do
    GenServer.cast(
      __MODULE__,
      {:report, :ingest_failure, Map.merge(%{sample: format_reason(reason)}, sample_meta)}
    )
  end

  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush, :infinity)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    interval = Keyword.get(opts, :flush_interval_ms, @flush_interval_ms)
    timer = Process.send_after(self(), :tick, interval)
    {:ok, %{buckets: %{}, timer: timer, interval: interval}}
  end

  @impl true
  def handle_cast({:report, kind, sample}, state) do
    buckets =
      Map.update(state.buckets, kind, {1, [sample]}, fn {count, samples} ->
        {count + 1, [sample | Enum.take(samples, @sample_limit - 1)]}
      end)

    {:noreply, %{state | buckets: buckets}}
  end

  @impl true
  def handle_info(:tick, state) do
    do_flush(state.buckets)
    timer = Process.send_after(self(), :tick, state.interval)
    {:noreply, %{state | buckets: %{}, timer: timer}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    Process.cancel_timer(state.timer)
    do_flush(state.buckets)
    timer = Process.send_after(self(), :tick, state.interval)
    {:reply, :ok, %{state | buckets: %{}, timer: timer}}
  end

  @impl true
  def terminate(_reason, %{buckets: buckets}) do
    do_flush(buckets)
  end

  defp do_flush(buckets) when map_size(buckets) == 0, do: :ok

  defp do_flush(buckets) do
    Enum.each(buckets, fn {kind, {count, samples}} ->
      Logger.warning(
        "engineering.errors.drop_alerter kind=#{kind} count=#{count} sample=#{inspect(List.first(samples))}"
      )
    end)
  end

  defp format_exception(%_{__exception__: true} = exception), do: Exception.message(exception)

  defp format_exception(other), do: inspect(other)

  defp format_reason(reason), do: inspect(reason)
end
