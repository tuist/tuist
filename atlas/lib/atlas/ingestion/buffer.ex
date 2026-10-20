defmodule Atlas.Ingestion.Buffer do
  @moduledoc """
  Per-table GenServer that buffers RowBinary ClickHouse writes and flushes
  them in batches on size, time, or shutdown.

  Ported from Hive. Flush failures do not crash the buffer: the batch is
  dropped and logged.
  """

  use GenServer

  alias Atlas.IngestRepo

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def insert(server, row_binary) do
    if sync_writes?() do
      GenServer.call(server, {:insert_and_flush, row_binary}, :infinity)
    else
      GenServer.cast(server, {:insert, row_binary})
    end
  end

  def flush(server) do
    GenServer.call(server, :flush, :infinity)
  end

  @impl true
  def init(opts) do
    buffer = opts[:buffer] || []
    max_buffer_size = opts[:max_buffer_size] || default_max_buffer_size()
    flush_interval_ms = opts[:flush_interval_ms] || default_flush_interval_ms()

    Process.flag(:trap_exit, true)
    timer = Process.send_after(self(), :tick, flush_interval_ms)

    {:ok,
     %{
       buffer: buffer,
       timer: timer,
       name: Keyword.fetch!(opts, :name),
       insert_sql: Keyword.fetch!(opts, :insert_sql),
       insert_opts: Keyword.fetch!(opts, :insert_opts),
       header: Keyword.fetch!(opts, :header),
       buffer_size: IO.iodata_length(buffer),
       max_buffer_size: max_buffer_size,
       flush_interval_ms: flush_interval_ms
     }}
  end

  @impl true
  def handle_cast({:insert, row_binary}, state) do
    state = %{
      state
      | buffer: [state.buffer | row_binary],
        buffer_size: state.buffer_size + IO.iodata_length(row_binary)
    }

    if state.buffer_size >= state.max_buffer_size do
      Logger.notice("#{state.name} buffer full, flushing to ClickHouse")
      Process.cancel_timer(state.timer)
      do_flush(state)
      new_timer = Process.send_after(self(), :tick, state.flush_interval_ms)
      {:noreply, %{state | buffer: [], timer: new_timer, buffer_size: 0}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    do_flush(state)
    timer = Process.send_after(self(), :tick, state.flush_interval_ms)
    {:noreply, %{state | buffer: [], buffer_size: 0, timer: timer}}
  end

  @impl true
  def handle_call({:insert_and_flush, row_binary}, _from, state) do
    state = %{
      state
      | buffer: [state.buffer | row_binary],
        buffer_size: state.buffer_size + IO.iodata_length(row_binary)
    }

    do_flush(state)
    {:reply, :ok, %{state | buffer: [], buffer_size: 0}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    %{timer: timer, flush_interval_ms: flush_interval_ms} = state
    Process.cancel_timer(timer)
    do_flush(state)
    new_timer = Process.send_after(self(), :tick, flush_interval_ms)
    {:reply, :ok, %{state | buffer: [], buffer_size: 0, timer: new_timer}}
  end

  @impl true
  def terminate(_reason, %{name: name} = state) do
    Logger.notice("Flushing #{name} buffer before shutdown...")
    do_flush(state)
  end

  defp do_flush(%{buffer: []}), do: :ok

  defp do_flush(state) do
    %{
      buffer: buffer,
      buffer_size: buffer_size,
      insert_opts: insert_opts,
      insert_sql: insert_sql,
      header: header,
      name: name
    } = state

    Logger.notice("Flushing #{buffer_size} byte(s) RowBinary from #{name}")

    try do
      IngestRepo.query!(insert_sql, [header | buffer], insert_opts)
    rescue
      error ->
        Logger.error("#{name} flush failed: #{Exception.message(error)}. Dropping #{buffer_size} byte(s).")
    end
  end

  defp default_flush_interval_ms do
    :atlas
    |> Application.get_env(IngestRepo, [])
    |> Keyword.get(:flush_interval_ms, 2_000)
  end

  defp default_max_buffer_size do
    :atlas
    |> Application.get_env(IngestRepo, [])
    |> Keyword.get(:max_buffer_size, 1_048_576)
  end

  defp sync_writes? do
    case Application.get_env(:atlas, IngestRepo) do
      config when is_list(config) -> Keyword.get(config, :sync_writes, false)
      _ -> false
    end
  end
end
